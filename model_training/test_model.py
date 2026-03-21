#!/usr/bin/env python3
"""
SMISDroid — Test Model on Custom Messages
==========================================

Works on Windows, macOS, and Linux.

Requirements:
    pip install tensorflow transformers pandas numpy scikit-learn

Usage:
    # Test with default testcase/test.csv
    python test_model.py

    # Test a single message
    python test_model.py "Your account is blocked. Verify at http://xyz.tk"

    # Test with a custom CSV file
    python test_model.py --file my_tests.csv

    # Interactive mode
    python test_model.py -i
"""

import os
import sys
import warnings

# Suppress TF/transformers warnings for clean output
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "3"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"
warnings.filterwarnings("ignore")

import numpy as np
import pandas as pd
import tensorflow as tf
from transformers import MobileBertTokenizer

tf.get_logger().setLevel("ERROR")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "output", "fraud_model.tflite")
MAX_SEQ_LENGTH = 128


def load_model():
    """Load MobileBERT tokenizer and TFLite interpreter."""
    if not os.path.exists(MODEL_PATH):
        print("ERROR: Model not found at: %s" % MODEL_PATH)
        print("Run train_mobilebert.py first to generate the model.")
        sys.exit(1)

    tokenizer = MobileBertTokenizer.from_pretrained("google/mobilebert-uncased")
    interp = tf.lite.Interpreter(model_path=MODEL_PATH)
    interp.allocate_tensors()
    return tokenizer, interp


def predict(tokenizer, interp, text):
    """Run inference on a single message. Returns (score, label)."""
    inp_d = interp.get_input_details()
    out_d = interp.get_output_details()

    tokens = tokenizer(
        text, max_length=MAX_SEQ_LENGTH,
        padding="max_length", truncation=True, return_tensors="np"
    )
    interp.set_tensor(inp_d[0]["index"], tokens["input_ids"].astype(np.int32))
    interp.invoke()
    score = float(interp.get_tensor(out_d[0]["index"])[0][0])

    if score > 0.6:
        label = "FRAUD"
    elif score > 0.3:
        label = "SUSPICIOUS"
    else:
        label = "SAFE"

    return score, label


def test_single(message):
    """Test a single message string."""
    print("Loading model...")
    tokenizer, interp = load_model()
    score, label = predict(tokenizer, interp, message)

    print()
    print("  Message:    %s" % message)
    print("  Prediction: %s (score=%.4f)" % (label, score))
    print()


def test_file(filepath):
    """Test all messages in a CSV file and print metrics."""
    if not os.path.exists(filepath):
        print("ERROR: File not found: %s" % filepath)
        sys.exit(1)

    print("Loading model...")
    tokenizer, interp = load_model()

    # Auto-detect separator (tab or comma)
    with open(filepath, encoding="utf-8", errors="replace") as f:
        first_line = f.readline()
    sep = "\t" if "\t" in first_line else ","

    df = pd.read_csv(filepath, sep=sep, encoding="utf-8", on_bad_lines="skip")

    # Find text column
    text_col = None
    for col in ["message_text", "text", "message", "sms", "content"]:
        if col in df.columns:
            text_col = col
            break
    if text_col is None:
        text_col = df.columns[0]

    # Find label column (optional)
    label_col = None
    for col in ["class_label", "label", "class", "category", "attack_type", "type"]:
        if col in df.columns:
            label_col = col
            break

    has_labels = label_col is not None

    print()
    print("=" * 80)
    print("  TEST RESULTS - %d messages" % len(df))
    if has_labels:
        print("  Labels column: %s" % label_col)
    print("=" * 80)
    print()

    y_true = []
    y_pred_list = []
    total = len(df)

    for i, row in df.iterrows():
        text = str(row[text_col])
        if not text or text == "nan":
            continue

        score, pred = predict(tokenizer, interp, text)

        if has_labels:
            true_label = str(row[label_col])
            true_binary = 0 if true_label == "benign" else 1
            pred_binary = 0 if pred == "SAFE" else 1
            y_true.append(true_binary)
            y_pred_list.append(pred_binary)

            is_correct = true_binary == pred_binary
            status = "OK" if is_correct else "WRONG"

            print("[%5s] #%-4d %-12s  True: %-25s  Score: %.4f" % (
                status, i + 1, pred, true_label, score))
        else:
            print("#%-4d %-12s  Score: %.4f  |  %s" % (
                i + 1, pred, score, text[:80]))

    if has_labels and len(y_true) > 0:
        from sklearn.metrics import (
            accuracy_score, precision_score, recall_score,
            f1_score, confusion_matrix
        )

        y_true = np.array(y_true)
        y_pred_arr = np.array(y_pred_list)

        acc = accuracy_score(y_true, y_pred_arr)
        prec = precision_score(y_true, y_pred_arr, zero_division=0)
        rec = recall_score(y_true, y_pred_arr, zero_division=0)
        f1 = f1_score(y_true, y_pred_arr, zero_division=0)
        fp_rate = 0.0
        fn_rate = 0.0

        cm = confusion_matrix(y_true, y_pred_arr, labels=[0, 1])
        if cm.size == 4:
            tn, fp, fn, tp = cm.ravel()
            if (tn + fp) > 0:
                fp_rate = fp / (tn + fp)
            if (fn + tp) > 0:
                fn_rate = fn / (fn + tp)
        else:
            tn, fp, fn, tp = 0, 0, 0, 0

        print()
        print("=" * 80)
        print("  METRICS")
        print("-" * 80)
        print("  Accuracy:         %.2f%%  (%d/%d correct)" % (acc * 100, int(acc * len(y_true)), len(y_true)))
        print("  Precision:        %.2f%%" % (prec * 100))
        print("  Recall:           %.2f%%" % (rec * 100))
        print("  F1-Score:         %.2f%%" % (f1 * 100))
        print("  False Positive:   %.2f%%  (%d safe flagged as fraud)" % (fp_rate * 100, fp))
        print("  False Negative:   %.2f%%  (%d fraud missed)" % (fn_rate * 100, fn))
        print("-" * 80)
        print("  Confusion Matrix:")
        print("                      Predicted SAFE    Predicted FRAUD")
        print("    Actually SAFE:       TN = %-8d    FP = %-8d" % (tn, fp))
        print("    Actually FRAUD:      FN = %-8d    TP = %-8d" % (fn, tp))
        print("=" * 80)
    print()


def interactive_mode():
    """Interactive mode - type messages one by one."""
    print("Loading model...")
    tokenizer, interp = load_model()
    print("Model loaded! Type a message to test (or 'quit' to exit)")
    print()

    while True:
        try:
            message = input("Message: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye!")
            break

        if not message or message.lower() in ("quit", "exit", "q"):
            print("Bye!")
            break

        score, label = predict(tokenizer, interp, message)
        print("  -> %s (score=%.4f)" % (label, score))
        print()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg in ("--file", "-f") and len(sys.argv) > 2:
            test_file(sys.argv[2])
        elif arg in ("--interactive", "-i"):
            interactive_mode()
        elif os.path.exists(arg):
            test_file(arg)
        else:
            # Treat as a message string
            test_single(" ".join(sys.argv[1:]))
    else:
        # Default: run testcase/test.csv if exists, otherwise interactive
        default_test = os.path.join(BASE_DIR, "testcase", "test.csv")
        if os.path.exists(default_test):
            test_file(default_test)
        else:
            interactive_mode()
