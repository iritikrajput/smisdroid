#!/usr/bin/env python3
"""
SMISDroid — MobileBERT Fine-Tuning Pipeline
=============================================

Fine-tunes MobileBERT (google/mobilebert-uncased) on train.csv for SMS fraud
detection, then exports to quantized TensorFlow Lite for on-device inference.

Dataset: train.csv with columns (message_text, class_label)
Labels:  benign -> 0, all fraud types -> 1

Usage:
    # Activate virtual environment
    source model_training/venv/bin/activate

    # Run training
    cd model_training
    python train_mobilebert.py

    # Output files are saved to output/ and copied to assets/

Hardware:
    - GPU recommended (~20 min on T4), CPU works (~30 min on modern CPU)
    - ~4 GB RAM required

Author: SMISDroid Development Team
Date:   March 21, 2026
"""

import os
import json
import random
import shutil
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix
from transformers import MobileBertTokenizer, TFMobileBertForSequenceClassification

# ─── Configuration ────────────────────────────────────────────

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH = os.path.join(BASE_DIR, "datasets", "train.csv")
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
ASSETS_DIR = os.path.join(BASE_DIR, "..", "assets")

MODEL_NAME = "google/mobilebert-uncased"
MAX_SEQ_LENGTH = 128
EPOCHS = 3
BATCH_SIZE = 16
LEARNING_RATE = 2e-5
TEST_SPLIT = 0.2
RANDOM_SEED = 42

VALID_LABELS = {
    "benign",
    "kyc_scam",
    "impersonation",
    "phishing_link",
    "fake_payment_portal",
    "account_block_scam",
}


# ─── Step 1: Load and Clean Dataset ──────────────────────────

def load_dataset(path):
    """
    Load train.csv and map to binary labels.
    benign -> 0 (legitimate), all other labels -> 1 (fraud)
    """
    print(f"Loading dataset: {path}")
    raw_df = pd.read_csv(path)
    print(f"  Raw rows: {len(raw_df)}")

    # Keep only valid rows
    df = raw_df[["message_text", "class_label"]].dropna()
    df = df[df["class_label"].isin(VALID_LABELS)].copy()

    # Binary mapping
    df["label"] = (df["class_label"] != "benign").astype(int)
    df = df.rename(columns={"message_text": "text"})

    # Deduplicate
    df = df.drop_duplicates(subset=["text"])
    df = df.sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)

    print(f"  Cleaned rows: {len(df)}")
    print(f"  Label distribution:")
    for label in sorted(VALID_LABELS):
        count = len(raw_df[raw_df["class_label"] == label])
        mapping = "0 (Safe)" if label == "benign" else "1 (Fraud)"
        print(f"    {label:25s} -> {mapping:12s} ({count} samples)")
    print(f"  Binary: Fraud={df['label'].sum()} ({df['label'].mean()*100:.1f}%) "
          f"| Safe={(df['label']==0).sum()} ({(df['label']==0).mean()*100:.1f}%)")

    return df[["text", "label"]]


# ─── Step 2: Tokenize ────────────────────────────────────────

def tokenize(texts, tokenizer):
    """Tokenize a list of texts using MobileBERT WordPiece tokenizer."""
    return tokenizer(
        texts,
        max_length=MAX_SEQ_LENGTH,
        padding="max_length",
        truncation=True,
        return_tensors="tf",
    )


# ─── Step 3: Create TF Datasets ──────────────────────────────

def make_tf_dataset(encodings, labels, batch_size, shuffle=False):
    """Create a batched tf.data.Dataset from tokenized encodings."""
    ds = tf.data.Dataset.from_tensor_slices((
        {
            "input_ids": encodings["input_ids"],
            "attention_mask": encodings["attention_mask"],
            "token_type_ids": encodings["token_type_ids"],
        },
        np.array(labels),
    ))
    if shuffle:
        ds = ds.shuffle(len(labels), seed=RANDOM_SEED)
    return ds.batch(batch_size).prefetch(tf.data.AUTOTUNE)


# ─── Step 4: Fine-Tune ───────────────────────────────────────

def train_model(train_ds, val_ds):
    """Load pre-trained MobileBERT and fine-tune on SMS data."""
    model = TFMobileBertForSequenceClassification.from_pretrained(
        MODEL_NAME, num_labels=2
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"],
    )
    print(f"  Parameters: {model.count_params():,}")

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS,
        verbose=1,
    )
    return model, history


# ─── Step 5: Evaluate ────────────────────────────────────────

def evaluate(model, val_ds, y_test):
    """Run evaluation and print classification report."""
    preds = model.predict(val_ds)
    y_pred = np.argmax(preds.logits, axis=-1)

    print(classification_report(y_test, y_pred, target_names=["Legitimate", "Fraud"]))

    cm = confusion_matrix(y_test, y_pred)
    print(f"Confusion Matrix:")
    print(f"  TN={cm[0][0]:>5}  FP={cm[0][1]:>5}")
    print(f"  FN={cm[1][0]:>5}  TP={cm[1][1]:>5}")

    accuracy = (cm[0][0] + cm[1][1]) / cm.sum()
    print(f"\nAccuracy:  {accuracy*100:.2f}%")
    print(f"Precision: {cm[1][1]/(cm[1][1]+cm[0][1])*100:.2f}%")
    print(f"Recall:    {cm[1][1]/(cm[1][1]+cm[1][0])*100:.2f}%")
    f1 = 2*cm[1][1] / (2*cm[1][1] + cm[0][1] + cm[1][0])
    print(f"F1-Score:  {f1*100:.2f}%")

    return y_pred, cm


# ─── Step 6: Export TFLite ────────────────────────────────────

def export_tflite(model, output_path):
    """
    Export model to quantized TFLite format.
    Wraps model to accept only input_ids and output fraud probability.
    """
    class TFLiteWrapper(tf.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        @tf.function(input_signature=[
            tf.TensorSpec(shape=[1, MAX_SEQ_LENGTH], dtype=tf.int32, name="input_ids")
        ])
        def predict(self, input_ids):
            attention_mask = tf.cast(tf.not_equal(input_ids, 0), tf.int32)
            token_type_ids = tf.zeros_like(input_ids)
            outputs = self.model(
                input_ids=input_ids,
                attention_mask=attention_mask,
                token_type_ids=token_type_ids,
                training=False,
            )
            probs = tf.nn.softmax(outputs.logits, axis=-1)
            return probs[:, 1:2]  # Fraud probability only

    wrapper = TFLiteWrapper(model)
    concrete_func = wrapper.predict.get_concrete_function()

    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func])
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter._experimental_lower_tensor_list_ops = False

    tflite_model = converter.convert()

    with open(output_path, "wb") as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / 1024 / 1024
    print(f"  Model saved: {output_path} ({size_mb:.1f} MB)")
    return tflite_model


# ─── Step 7: Verify TFLite ───────────────────────────────────

def verify_tflite(tflite_path, tokenizer, X_test, y_test):
    """Run all test samples through TFLite interpreter and report accuracy."""
    interp = tf.lite.Interpreter(model_path=tflite_path)
    interp.allocate_tensors()
    inp_d = interp.get_input_details()
    out_d = interp.get_output_details()

    correct = 0
    n = len(X_test)

    for i in range(n):
        tokens = tokenizer(
            X_test[i], max_length=MAX_SEQ_LENGTH,
            padding="max_length", truncation=True, return_tensors="np"
        )
        interp.set_tensor(inp_d[0]["index"], tokens["input_ids"].astype(np.int32))
        interp.invoke()
        score = interp.get_tensor(out_d[0]["index"])[0][0]
        if (1 if score > 0.5 else 0) == y_test[i]:
            correct += 1
        if (i + 1) % 300 == 0:
            print(f"    {i+1}/{n} — {correct/(i+1)*100:.1f}%")

    accuracy = correct / n * 100
    print(f"  TFLite accuracy: {correct}/{n} ({accuracy:.2f}%)")
    return correct, n


# ─── Step 8: Export Assets ────────────────────────────────────

def export_assets(tokenizer, model, tflite_model, correct, n_test):
    """Export vocabulary, config, and weights metadata."""
    # Vocabulary
    vocab = tokenizer.get_vocab()
    sorted_vocab = {k: int(v) for k, v in sorted(vocab.items(), key=lambda x: x[1])}
    vocab_path = os.path.join(OUTPUT_DIR, "vocabulary.json")
    with open(vocab_path, "w") as f:
        json.dump(sorted_vocab, f)
    print(f"  Vocabulary: {vocab_path} ({len(sorted_vocab)} tokens)")

    # Config
    config = {
        "model_type": "mobilebert",
        "model_name": MODEL_NAME,
        "max_seq_length": MAX_SEQ_LENGTH,
        "vocab_size": tokenizer.vocab_size,
        "input_type": "token_ids",
        "output_type": "fraud_probability",
        "threshold_safe": 0.3,
        "threshold_suspicious": 0.6,
        "pad_token_id": tokenizer.pad_token_id,
        "cls_token_id": tokenizer.cls_token_id,
        "sep_token_id": tokenizer.sep_token_id,
        "unk_token_id": tokenizer.unk_token_id,
        "version": "1.0.0",
        "training": {
            "epochs": EPOCHS,
            "batch_size": BATCH_SIZE,
            "learning_rate": LEARNING_RATE,
            "train_samples": int(n_test / TEST_SPLIT * (1 - TEST_SPLIT)),
            "test_samples": n_test,
            "test_accuracy": round(correct / n_test, 4),
        },
    }
    config_path = os.path.join(OUTPUT_DIR, "nlp_config.json")
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"  Config: {config_path}")

    # Weights metadata
    weights = {
        "type": "mobilebert",
        "base_model": MODEL_NAME,
        "total_params": int(model.count_params()),
        "quantization": "dynamic_range",
        "tflite_size_bytes": len(tflite_model),
    }
    weights_path = os.path.join(OUTPUT_DIR, "model_weights.json")
    with open(weights_path, "w") as f:
        json.dump(weights, f, indent=2)
    print(f"  Weights: {weights_path}")


# ─── Step 9: Copy to Flutter Assets ──────────────────────────

def copy_to_assets():
    """Copy output files to the Flutter assets directory."""
    copies = [
        ("fraud_model.tflite", os.path.join(ASSETS_DIR, "models")),
        ("vocabulary.json", os.path.join(ASSETS_DIR, "nlp")),
        ("nlp_config.json", os.path.join(ASSETS_DIR, "nlp")),
        ("model_weights.json", os.path.join(ASSETS_DIR, "nlp")),
    ]
    for filename, dst_dir in copies:
        src = os.path.join(OUTPUT_DIR, filename)
        os.makedirs(dst_dir, exist_ok=True)
        dst = os.path.join(dst_dir, filename)
        shutil.copy2(src, dst)
        size_kb = os.path.getsize(dst) / 1024
        print(f"  -> {dst} ({size_kb:.1f} KB)")


# ─── Main ─────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  SMISDroid — MobileBERT Training Pipeline")
    print("=" * 60)
    print(f"TensorFlow: {tf.__version__}")

    # GPU check
    gpus = tf.config.list_physical_devices("GPU")
    if gpus:
        print(f"GPU: {gpus}")
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
    else:
        print("GPU: None — training on CPU")

    # Seed everything
    random.seed(RANDOM_SEED)
    np.random.seed(RANDOM_SEED)
    tf.random.set_seed(RANDOM_SEED)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Step 1: Load dataset
    print("\n--- Step 1: Loading Dataset ---")
    df = load_dataset(DATASET_PATH)

    # Step 2: Split
    print("\n--- Step 2: Train/Test Split ---")
    X_train, X_test, y_train, y_test = train_test_split(
        df["text"].tolist(), df["label"].tolist(),
        test_size=TEST_SPLIT, random_state=RANDOM_SEED, stratify=df["label"],
    )
    print(f"  Train: {len(X_train)} | Test: {len(X_test)}")

    # Step 3: Tokenize
    print("\n--- Step 3: Tokenizing ---")
    tokenizer = MobileBertTokenizer.from_pretrained(MODEL_NAME)
    train_enc = tokenize(X_train, tokenizer)
    test_enc = tokenize(X_test, tokenizer)
    print(f"  Train shape: {train_enc['input_ids'].shape}")
    print(f"  Test shape:  {test_enc['input_ids'].shape}")

    train_ds = make_tf_dataset(train_enc, y_train, BATCH_SIZE, shuffle=True)
    val_ds = make_tf_dataset(test_enc, y_test, BATCH_SIZE, shuffle=False)

    # Step 4: Fine-tune
    print("\n--- Step 4: Fine-Tuning MobileBERT ---")
    model, history = train_model(train_ds, val_ds)

    # Step 5: Evaluate
    print("\n--- Step 5: Evaluation ---")
    y_pred, cm = evaluate(model, val_ds, y_test)

    # Step 6: Export TFLite
    print("\n--- Step 6: Exporting TFLite ---")
    tflite_path = os.path.join(OUTPUT_DIR, "fraud_model.tflite")
    tflite_model = export_tflite(model, tflite_path)

    # Step 7: Verify TFLite
    print("\n--- Step 7: Verifying TFLite ---")
    correct, n_test = verify_tflite(tflite_path, tokenizer, X_test, y_test)

    # Step 8: Export assets
    print("\n--- Step 8: Exporting Flutter Assets ---")
    export_assets(tokenizer, model, tflite_model, correct, n_test)

    # Step 9: Copy to Flutter assets
    print("\n--- Step 9: Copying to Flutter Assets ---")
    copy_to_assets()

    print("\n" + "=" * 60)
    print("  DONE! Run: flutter build apk --debug")
    print("=" * 60)


if __name__ == "__main__":
    main()
