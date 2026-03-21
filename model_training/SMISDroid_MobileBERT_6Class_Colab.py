#!/usr/bin/env python3
"""
SMISDroid — MobileBERT 6-Class Training for Google Colab
=========================================================
Upload this file + train.csv to Colab, set GPU runtime, run it.

Steps in Colab:
1. Runtime → Change runtime type → T4 GPU
2. Upload train.csv when prompted
3. Run all cells (or run this as: !python SMISDroid_MobileBERT_6Class_Colab.py)
4. Download output files at the end
"""

# ════════════════════════════════════════════════════════════════
# CELL 1: Install dependencies
# ════════════════════════════════════════════════════════════════
import subprocess, sys
subprocess.check_call([sys.executable, "-m", "pip", "install", "-q",
    "transformers<5", "tf-keras", "datasets", "scikit-learn", "pandas", "numpy"])

# ════════════════════════════════════════════════════════════════
# CELL 2: Imports + GPU check
# ════════════════════════════════════════════════════════════════
import os, json, random, shutil
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.utils.class_weight import compute_class_weight
from transformers import MobileBertTokenizer, TFMobileBertForSequenceClassification

print("TensorFlow:", tf.__version__)
gpus = tf.config.list_physical_devices("GPU")
print("GPUs:", gpus)
if gpus:
    for gpu in gpus:
        tf.config.experimental.set_memory_growth(gpu, True)
    print("GPU memory growth enabled")
else:
    print("WARNING: No GPU — training will be very slow!")

RANDOM_SEED = 42
random.seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)
tf.random.set_seed(RANDOM_SEED)

# ════════════════════════════════════════════════════════════════
# CELL 3: Upload dataset
# ════════════════════════════════════════════════════════════════
DATASET_PATH = "train.csv"
if not os.path.exists(DATASET_PATH):
    try:
        from google.colab import files
        print("Upload train.csv:")
        uploaded = files.upload()
        DATASET_PATH = list(uploaded.keys())[0]
    except ImportError:
        raise FileNotFoundError("train.csv not found. Upload it or place in current directory.")

# ════════════════════════════════════════════════════════════════
# CELL 4: Load and prepare dataset
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 1: Loading Dataset")
print("=" * 60)

raw_df = pd.read_csv(DATASET_PATH)

LABELS = [
    "benign",
    "kyc_scam",
    "impersonation",
    "phishing_link",
    "fake_payment_portal",
    "account_block_scam",
]
NUM_CLASSES = len(LABELS)
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
ID_TO_LABEL = {str(i): l for l, i in LABEL_TO_ID.items()}

df = raw_df[["message_text", "class_label"]].dropna()
df = df[df["class_label"].isin(LABELS)].copy()
df["label"] = df["class_label"].map(LABEL_TO_ID)
df = df.rename(columns={"message_text": "text"})
df = df.drop_duplicates(subset=["text"])
df = df.sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)

print("Total samples:", len(df))
print("\nClass distribution:")
for lbl in LABELS:
    count = int((df["class_label"] == lbl).sum())
    pct = count / len(df) * 100
    print("  [%d] %-25s: %5d (%.1f%%)" % (LABEL_TO_ID[lbl], lbl, count, pct))

# ════════════════════════════════════════════════════════════════
# CELL 5: Train/Test Split
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 2: Train/Test Split")
print("=" * 60)

X_train, X_test, y_train, y_test = train_test_split(
    df["text"].tolist(), df["label"].tolist(),
    test_size=0.2, random_state=RANDOM_SEED, stratify=df["label"],
)
print("Train:", len(X_train), "| Test:", len(X_test))

# Class weights for imbalanced data
cw = compute_class_weight("balanced", classes=np.arange(NUM_CLASSES), y=np.array(y_train))
class_weights = {i: float(w) for i, w in enumerate(cw)}
print("\nClass weights (balanced):")
for i, lbl in enumerate(LABELS):
    print("  %-25s: %.3f" % (lbl, class_weights[i]))

# ════════════════════════════════════════════════════════════════
# CELL 6: Tokenize
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 3: Tokenizing with MobileBERT")
print("=" * 60)

MODEL_NAME = "google/mobilebert-uncased"
MAX_SEQ_LENGTH = 128
tokenizer = MobileBertTokenizer.from_pretrained(MODEL_NAME)

train_enc = tokenizer(X_train, max_length=MAX_SEQ_LENGTH, padding="max_length",
                      truncation=True, return_tensors="tf")
test_enc = tokenizer(X_test, max_length=MAX_SEQ_LENGTH, padding="max_length",
                     truncation=True, return_tensors="tf")
print("Train tokens shape:", train_enc["input_ids"].shape)
print("Test tokens shape: ", test_enc["input_ids"].shape)

BATCH_SIZE = 32  # Larger batch on GPU

train_ds = tf.data.Dataset.from_tensor_slices((
    {"input_ids": train_enc["input_ids"],
     "attention_mask": train_enc["attention_mask"],
     "token_type_ids": train_enc["token_type_ids"]},
    np.array(y_train)
)).shuffle(len(y_train), seed=RANDOM_SEED).batch(BATCH_SIZE).prefetch(tf.data.AUTOTUNE)

test_ds = tf.data.Dataset.from_tensor_slices((
    {"input_ids": test_enc["input_ids"],
     "attention_mask": test_enc["attention_mask"],
     "token_type_ids": test_enc["token_type_ids"]},
    np.array(y_test)
)).batch(BATCH_SIZE).prefetch(tf.data.AUTOTUNE)

# ════════════════════════════════════════════════════════════════
# CELL 7: Fine-tune MobileBERT
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 4: Fine-Tuning MobileBERT (%d classes)" % NUM_CLASSES)
print("=" * 60)

EPOCHS = 8
LEARNING_RATE = 3e-5

model = TFMobileBertForSequenceClassification.from_pretrained(
    MODEL_NAME, num_labels=NUM_CLASSES
)
model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=LEARNING_RATE),
    loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
    metrics=["accuracy"],
)
print("Parameters: {:,}".format(model.count_params()))
print("Epochs:", EPOCHS)
print("Batch size:", BATCH_SIZE)
print("Learning rate:", LEARNING_RATE)

early_stop = tf.keras.callbacks.EarlyStopping(
    monitor="val_accuracy", patience=2,
    restore_best_weights=True, verbose=1
)

history = model.fit(
    train_ds,
    validation_data=test_ds,
    epochs=EPOCHS,
    class_weight=class_weights,
    callbacks=[early_stop],
    verbose=1,
)

# ════════════════════════════════════════════════════════════════
# CELL 8: Evaluation
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 5: Evaluation")
print("=" * 60)

preds_out = model.predict(test_ds)
y_pred = np.argmax(preds_out.logits, axis=-1)

print("\nPer-class Classification Report:")
print(classification_report(y_test, y_pred, target_names=LABELS, digits=4))

cm = confusion_matrix(y_test, y_pred)
print("Confusion Matrix:")
header = "%-25s" % "" + "".join(["%-8s" % l[:7] for l in LABELS])
print(header)
for i, row in enumerate(cm):
    print("%-25s" % LABELS[i] + "".join(["%-8d" % v for v in row]))

overall_acc = np.sum(np.array(y_test) == y_pred) / len(y_test)
print("\nOverall Accuracy: %.2f%%" % (overall_acc * 100))

# Per-class accuracy
print("\nPer-class Accuracy:")
for i, lbl in enumerate(LABELS):
    mask = np.array(y_test) == i
    if mask.sum() > 0:
        cls_acc = (y_pred[mask] == i).sum() / mask.sum() * 100
        print("  %-25s: %.1f%% (%d/%d)" % (lbl, cls_acc, (y_pred[mask] == i).sum(), mask.sum()))

# ════════════════════════════════════════════════════════════════
# CELL 9: Export to TFLite
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 6: Exporting to TFLite")
print("=" * 60)

os.makedirs("output", exist_ok=True)

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
        # Return ALL 6 class probabilities
        return tf.nn.softmax(outputs.logits, axis=-1)

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

tflite_path = "output/fraud_model.tflite"
with open(tflite_path, "wb") as f:
    f.write(tflite_model)
print("Model saved: %s (%.1f MB)" % (tflite_path, len(tflite_model) / 1024 / 1024))

# ════════════════════════════════════════════════════════════════
# CELL 10: Verify TFLite model
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 7: Verifying TFLite")
print("=" * 60)

interp = tf.lite.Interpreter(model_path=tflite_path)
interp.allocate_tensors()
inp_d = interp.get_input_details()
out_d = interp.get_output_details()
print("Input shape: ", inp_d[0]["shape"])
print("Output shape:", out_d[0]["shape"], " (6 class probabilities)")

correct = 0
n = len(X_test)
for i in range(n):
    t = tokenizer(X_test[i], max_length=MAX_SEQ_LENGTH, padding="max_length",
                  truncation=True, return_tensors="np")
    interp.set_tensor(inp_d[0]["index"], t["input_ids"].astype(np.int32))
    interp.invoke()
    probs = interp.get_tensor(out_d[0]["index"])[0]
    pred = int(np.argmax(probs))
    if pred == y_test[i]:
        correct += 1
    if (i + 1) % 300 == 0:
        print("  %d/%d — %.1f%%" % (i + 1, n, correct / (i + 1) * 100))

tflite_acc = correct / n
print("\nTFLite Accuracy: %d/%d (%.2f%%)" % (correct, n, tflite_acc * 100))

# ════════════════════════════════════════════════════════════════
# CELL 11: Export vocabulary + config + metadata
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 8: Exporting Assets")
print("=" * 60)

# Vocabulary
vocab = tokenizer.get_vocab()
sorted_vocab = {k: int(v) for k, v in sorted(vocab.items(), key=lambda x: x[1])}
with open("output/vocabulary.json", "w") as f:
    json.dump(sorted_vocab, f)
print("Vocabulary: output/vocabulary.json (%d tokens)" % len(sorted_vocab))

# Config
config = {
    "model_type": "mobilebert",
    "model_name": MODEL_NAME,
    "max_seq_length": MAX_SEQ_LENGTH,
    "vocab_size": tokenizer.vocab_size,
    "num_classes": NUM_CLASSES,
    "labels": LABELS,
    "label_to_id": LABEL_TO_ID,
    "id_to_label": ID_TO_LABEL,
    "input_type": "token_ids",
    "output_type": "class_probabilities",
    "pad_token_id": tokenizer.pad_token_id,
    "cls_token_id": tokenizer.cls_token_id,
    "sep_token_id": tokenizer.sep_token_id,
    "unk_token_id": tokenizer.unk_token_id,
    "version": "2.0.0",
    "training": {
        "epochs": EPOCHS,
        "batch_size": BATCH_SIZE,
        "learning_rate": LEARNING_RATE,
        "train_samples": len(X_train),
        "test_samples": len(X_test),
        "test_accuracy": round(tflite_acc, 4),
        "class_weights": {LABELS[i]: round(w, 3) for i, w in class_weights.items()},
    },
}
with open("output/nlp_config.json", "w") as f:
    json.dump(config, f, indent=2)
print("Config: output/nlp_config.json")

# Weights metadata
weights_meta = {
    "type": "mobilebert",
    "base_model": MODEL_NAME,
    "total_params": int(model.count_params()),
    "num_classes": NUM_CLASSES,
    "labels": LABELS,
    "quantization": "dynamic_range",
    "tflite_size_bytes": len(tflite_model),
}
with open("output/model_weights.json", "w") as f:
    json.dump(weights_meta, f, indent=2)
print("Weights: output/model_weights.json")

# ════════════════════════════════════════════════════════════════
# CELL 12: Download files (Colab) or print paths (local)
# ════════════════════════════════════════════════════════════════
print("\n" + "=" * 60)
print("  STEP 9: Download Trained Model")
print("=" * 60)

output_files = [
    "output/fraud_model.tflite",
    "output/vocabulary.json",
    "output/nlp_config.json",
    "output/model_weights.json",
]

for f in output_files:
    size = os.path.getsize(f) / 1024
    unit = "KB"
    if size > 1024:
        size /= 1024
        unit = "MB"
    print("  %s (%.1f %s)" % (f, size, unit))

try:
    from google.colab import files as colab_files
    print("\nDownloading files...")
    for f in output_files:
        colab_files.download(f)
    print("Download started! Check your browser downloads.")
except ImportError:
    print("\nNot running on Colab. Copy these files to your Flutter project:")
    print("  output/fraud_model.tflite  →  assets/models/fraud_model.tflite")
    print("  output/vocabulary.json     →  assets/nlp/vocabulary.json")
    print("  output/nlp_config.json     →  assets/nlp/nlp_config.json")
    print("  output/model_weights.json  →  assets/nlp/model_weights.json")

print("\n" + "=" * 60)
print("  TRAINING COMPLETE!")
print("  Model: MobileBERT 6-class (%.1f MB)" % (len(tflite_model) / 1024 / 1024))
print("  Classes: %s" % str(LABELS))
print("  TFLite Accuracy: %.2f%%" % (tflite_acc * 100))
print("=" * 60)
