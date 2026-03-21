#!/usr/bin/env python3
"""
SMISDroid — MobileBERT Binary Classification Training
======================================================

Fine-tunes MobileBERT (google/mobilebert-uncased) on train.csv for binary
SMS fraud detection (fraud vs safe), then exports to quantized TFLite
for on-device inference.

Dataset: train.csv with columns (message_text, class_label)
Labels:  benign → 0 (Safe), all fraud types → 1 (Fraud)

Fraud subtypes (kyc_scam, impersonation, phishing_link, fake_payment_portal,
account_block_scam) are classified separately by the rule engine in the app.

Usage:
    # Activate virtual environment
    source model_training/venv/bin/activate

    # Run training
    cd model_training
    python train_mobilebert.py

    # Or on Google Colab: upload this file + train.csv, set GPU runtime, run it

Output files (saved to output/ and copied to assets/):
    - fraud_model.tflite     — Quantized TFLite model (~25 MB)
    - vocabulary.json        — MobileBERT WordPiece vocabulary (30522 tokens)
    - nlp_config.json        — Model configuration + training metadata
    - model_weights.json     — Model size + parameter count

Hardware:
    - GPU recommended (~20 min on T4)
    - CPU works (~45 min on modern CPU)
    - ~4 GB RAM required

Author: SMISDroid Development Team
Date:   March 2026
"""

import os
import json
import random
import shutil
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix, f1_score
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
    benign → 0 (safe), all fraud types → 1 (fraud)
    """
    print("Loading dataset: %s" % path)
    raw_df = pd.read_csv(path)
    print("  Raw rows: %d" % len(raw_df))

    # Keep only valid rows
    df = raw_df[["message_text", "class_label"]].dropna()
    df = df[df["class_label"].isin(VALID_LABELS)].copy()

    # Binary mapping: benign=0, everything else=1
    df["label"] = (df["class_label"] != "benign").astype(int)
    df = df.rename(columns={"message_text": "text"})

    # Deduplicate and shuffle
    df = df.drop_duplicates(subset=["text"])
    df = df.sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)

    print("  Cleaned rows: %d" % len(df))
    print("  Label distribution:")
    for label in sorted(VALID_LABELS):
        count = int((df["class_label"] == label).sum())
        mapping = "0 (Safe)" if label == "benign" else "1 (Fraud)"
        print("    %-25s -> %-12s (%d samples)" % (label, mapping, count))

    fraud_count = int(df["label"].sum())
    safe_count = len(df) - fraud_count
    print("  Binary split: Fraud=%d (%.1f%%) | Safe=%d (%.1f%%)" % (
        fraud_count, fraud_count / len(df) * 100,
        safe_count, safe_count / len(df) * 100))

    return df[["text", "label"]]


# ─── Step 2: Tokenize ────────────────────────────────────────

def tokenize(texts, tokenizer):
    """Tokenize texts using MobileBERT WordPiece tokenizer."""
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
    """Load pre-trained MobileBERT and fine-tune for binary classification."""
    model = TFMobileBertForSequenceClassification.from_pretrained(
        MODEL_NAME, num_labels=2
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"],
    )
    print("  Parameters: {:,}".format(model.count_params()))
    print("  Epochs: %d | Batch size: %d | LR: %.0e" % (EPOCHS, BATCH_SIZE, LEARNING_RATE))

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

    print(classification_report(
        y_test, y_pred,
        target_names=["Legitimate", "Fraud"],
        digits=4,
    ))

    cm = confusion_matrix(y_test, y_pred)
    print("Confusion Matrix:")
    print("                  Predicted Safe  Predicted Fraud")
    print("  Actually Safe:     TN=%5d        FP=%5d" % (cm[0][0], cm[0][1]))
    print("  Actually Fraud:    FN=%5d        TP=%5d" % (cm[1][0], cm[1][1]))

    accuracy = (cm[0][0] + cm[1][1]) / cm.sum()
    precision = cm[1][1] / (cm[1][1] + cm[0][1]) if (cm[1][1] + cm[0][1]) > 0 else 0
    recall = cm[1][1] / (cm[1][1] + cm[1][0]) if (cm[1][1] + cm[1][0]) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    print("\nAccuracy:    %.2f%%" % (accuracy * 100))
    print("Precision:   %.2f%%" % (precision * 100))
    print("Recall:      %.2f%%" % (recall * 100))
    print("F1-Score:    %.2f%%" % (f1 * 100))
    print("FP Rate:     %.2f%%" % (cm[0][1] / (cm[0][0] + cm[0][1]) * 100))
    print("FN Rate:     %.2f%%" % (cm[1][0] / (cm[1][0] + cm[1][1]) * 100))

    return y_pred, cm, accuracy


# ─── Step 6: Export TFLite ────────────────────────────────────

def export_tflite(model, output_path):
    """
    Export model to quantized TFLite format.
    Output: single float — fraud probability (0.0-1.0)
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
    print("  Model saved: %s (%.1f MB)" % (output_path, size_mb))
    print("  Output: [1, 1] — single fraud probability float")
    return tflite_model


# ─── Step 7: Verify TFLite ───────────────────────────────────

def verify_tflite(tflite_path, tokenizer, X_test, y_test):
    """Run all test samples through TFLite interpreter and report accuracy."""
    interp = tf.lite.Interpreter(model_path=tflite_path)
    interp.allocate_tensors()
    inp_d = interp.get_input_details()
    out_d = interp.get_output_details()

    print("  Input shape:  %s" % str(inp_d[0]["shape"]))
    print("  Output shape: %s" % str(out_d[0]["shape"]))

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
            print("    %d/%d — %.1f%%" % (i + 1, n, correct / (i + 1) * 100))

    accuracy = correct / n * 100
    print("  TFLite accuracy: %d/%d (%.2f%%)" % (correct, n, accuracy))
    return correct, n


# ─── Step 8: Export Assets ────────────────────────────────────

def export_assets(tokenizer, model, tflite_model, correct, n_test, n_train, accuracy):
    """Export vocabulary, config, and weights metadata."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Vocabulary
    vocab = tokenizer.get_vocab()
    sorted_vocab = {k: int(v) for k, v in sorted(vocab.items(), key=lambda x: x[1])}
    vocab_path = os.path.join(OUTPUT_DIR, "vocabulary.json")
    with open(vocab_path, "w") as f:
        json.dump(sorted_vocab, f)
    print("  Vocabulary: %s (%d tokens)" % (vocab_path, len(sorted_vocab)))

    # Config
    config = {
        "model_type": "mobilebert",
        "model_name": MODEL_NAME,
        "max_seq_length": MAX_SEQ_LENGTH,
        "vocab_size": tokenizer.vocab_size,
        "num_labels": 2,
        "labels": ["benign", "fraud"],
        "input_type": "token_ids",
        "output_type": "fraud_probability",
        "detection_mode": "hybrid",
        "binary_model": "fraud_model.tflite",
        "subtype_classifier": "rule_engine",
        "subtype_labels": [
            "kyc_scam", "impersonation", "phishing_link",
            "fake_payment_portal", "account_block_scam",
        ],
        "threshold_safe": 0.3,
        "threshold_suspicious": 0.6,
        "pad_token_id": tokenizer.pad_token_id,
        "cls_token_id": tokenizer.cls_token_id,
        "sep_token_id": tokenizer.sep_token_id,
        "unk_token_id": tokenizer.unk_token_id,
        "version": "2.1.0",
        "training": {
            "type": "binary",
            "epochs": EPOCHS,
            "batch_size": BATCH_SIZE,
            "learning_rate": LEARNING_RATE,
            "train_samples": n_train,
            "test_samples": n_test,
            "test_accuracy": round(correct / n_test, 4),
            "keras_accuracy": round(accuracy, 4),
        },
    }
    config_path = os.path.join(OUTPUT_DIR, "nlp_config.json")
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print("  Config: %s" % config_path)

    # Weights metadata
    weights = {
        "type": "mobilebert",
        "base_model": MODEL_NAME,
        "total_params": int(model.count_params()),
        "num_labels": 2,
        "quantization": "dynamic_range",
        "tflite_size_bytes": len(tflite_model),
    }
    weights_path = os.path.join(OUTPUT_DIR, "model_weights.json")
    with open(weights_path, "w") as f:
        json.dump(weights, f, indent=2)
    print("  Weights: %s" % weights_path)


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
        print("  -> %s (%.1f KB)" % (dst, size_kb))


# ─── Main ─────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  SMISDroid — MobileBERT Binary Training Pipeline")
    print("=" * 60)
    print("TensorFlow: %s" % tf.__version__)

    # GPU check
    gpus = tf.config.list_physical_devices("GPU")
    if gpus:
        print("GPU: %s" % str(gpus))
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
    else:
        print("GPU: None — training on CPU")

    # Seed everything
    random.seed(RANDOM_SEED)
    np.random.seed(RANDOM_SEED)
    tf.random.set_seed(RANDOM_SEED)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Step 1
    print("\n--- Step 1: Loading Dataset ---")
    df = load_dataset(DATASET_PATH)

    # Step 2
    print("\n--- Step 2: Train/Test Split ---")
    X_train, X_test, y_train, y_test = train_test_split(
        df["text"].tolist(), df["label"].tolist(),
        test_size=TEST_SPLIT, random_state=RANDOM_SEED, stratify=df["label"],
    )
    print("  Train: %d | Test: %d" % (len(X_train), len(X_test)))

    # Step 3
    print("\n--- Step 3: Tokenizing ---")
    tokenizer = MobileBertTokenizer.from_pretrained(MODEL_NAME)
    train_enc = tokenize(X_train, tokenizer)
    test_enc = tokenize(X_test, tokenizer)
    print("  Train shape: %s" % str(train_enc["input_ids"].shape))
    print("  Test shape:  %s" % str(test_enc["input_ids"].shape))

    train_ds = make_tf_dataset(train_enc, y_train, BATCH_SIZE, shuffle=True)
    val_ds = make_tf_dataset(test_enc, y_test, BATCH_SIZE, shuffle=False)

    # Step 4
    print("\n--- Step 4: Fine-Tuning MobileBERT (Binary) ---")
    model, history = train_model(train_ds, val_ds)

    # Step 5
    print("\n--- Step 5: Evaluation ---")
    y_pred, cm, accuracy = evaluate(model, val_ds, y_test)

    # Step 6
    print("\n--- Step 6: Exporting TFLite ---")
    tflite_path = os.path.join(OUTPUT_DIR, "fraud_model.tflite")
    tflite_model = export_tflite(model, tflite_path)

    # Step 7
    print("\n--- Step 7: Verifying TFLite ---")
    correct, n_test = verify_tflite(tflite_path, tokenizer, X_test, y_test)

    # Step 8
    print("\n--- Step 8: Exporting Flutter Assets ---")
    export_assets(tokenizer, model, tflite_model, correct, n_test, len(X_train), accuracy)

    # Step 9
    print("\n--- Step 9: Copying to Flutter Assets ---")
    copy_to_assets()

    print("\n" + "=" * 60)
    print("  DONE!")
    print("  Model: Binary MobileBERT (fraud vs safe)")
    print("  TFLite accuracy: %d/%d (%.2f%%)" % (correct, n_test, correct / n_test * 100))
    print("  Fraud subtypes: classified by rule engine in the app")
    print("  Run: flutter build apk --debug")
    print("=" * 60)


if __name__ == "__main__":
    main()
