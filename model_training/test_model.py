#!/usr/bin/env python3
"""
SMISDroid — Test Model on Custom Messages
==========================================

Usage:
    # Test with test.csv file
    python test_model.py

    # Test a single message
    python test_model.py "Your account is blocked. Verify at http://xyz.tk"

    # Test with a custom CSV file
    python test_model.py --file my_tests.csv
"""

import os
import sys
import numpy as np
import pandas as pd
import tensorflow as tf
from transformers import MobileBertTokenizer

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "output", "fraud_model.tflite")
MAX_SEQ_LENGTH = 128


def load_model():
    tokenizer = MobileBertTokenizer.from_pretrained("google/mobilebert-uncased")
    interp = tf.lite.Interpreter(model_path=MODEL_PATH)
    interp.allocate_tensors()
    return tokenizer, interp


def predict(tokenizer, interp, text):
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
    print("Loading model...")
    tokenizer, interp = load_model()
    score, label = predict(tokenizer, interp, message)

    print("\nMessage:    %s" % message)
    print("Prediction: %s (score=%.4f)" % (label, score))


def test_file(filepath):
    print("Loading model...")
    tokenizer, interp = load_model()

    # Auto-detect separator
    with open(filepath) as f:
        first_line = f.readline()
    sep = "\t" if "\t" in first_line else ","

    df = pd.read_csv(filepath, sep=sep)

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

    print("\n" + "=" * 80)
    print("  TEST RESULTS — %d messages" % len(df))
    print("=" * 80 + "\n")

    y_true = []
    y_pred_list = []
    total = len(df)

    for i, row in df.iterrows():
        text = str(row[text_col])
        score, pred = predict(tokenizer, interp, text)

        if has_labels:
            true_label = str(row[label_col])
            true_binary = 0 if true_label == "benign" else 1
            pred_binary = 0 if pred == "SAFE" else 1
            y_true.append(true_binary)
            y_pred_list.append(pred_binary)

            is_correct = true_binary == pred_binary
            status = "OK" if is_correct else "WRONG"

            print("[%5s] #%-3d  %-12s  True: %-25s  Score: %.4f" % (
                status, i + 1, pred, true_label, score))
        else:
            print("#%-3d  %-12s  Score: %.4f  |  %s" % (
                i + 1, pred, score, text[:80]))

    if has_labels and len(y_true) > 0:
        from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, confusion_matrix

        y_true = np.array(y_true)
        y_pred_arr = np.array(y_pred_list)

        acc = accuracy_score(y_true, y_pred_arr)
        prec = precision_score(y_true, y_pred_arr, zero_division=0)
        rec = recall_score(y_true, y_pred_arr, zero_division=0)
        f1 = f1_score(y_true, y_pred_arr, zero_division=0)

        cm = confusion_matrix(y_true, y_pred_arr, labels=[0, 1])
        tn, fp, fn, tp = cm.ravel() if cm.size == 4 else (0, 0, 0, 0)

        print("\n" + "=" * 80)
        print("  METRICS")
        print("=" * 80)
        print("  Accuracy:    %.2f%% (%d/%d)" % (acc * 100, int(acc * total), total))
        print("  Precision:   %.2f%%" % (prec * 100))
        print("  Recall:      %.2f%%" % (rec * 100))
        print("  F1-Score:    %.2f%%" % (f1 * 100))
        print()
        print("  Confusion Matrix:")
        print("                    Predicted SAFE  Predicted FRAUD")
        print("    Actually SAFE:     TN=%5d        FP=%5d" % (tn, fp))
        print("    Actually FRAUD:    FN=%5d        TP=%5d" % (fn, tp))
        print("=" * 80)
    print()


def interactive_mode():
    print("Loading model...")
    tokenizer, interp = load_model()
    print("Model loaded! Type a message to test (or 'quit' to exit)\n")

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
        print("  -> %s (score=%.4f)\n" % (label, score))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "--file" and len(sys.argv) > 2:
            test_file(sys.argv[2])
        elif arg == "--interactive" or arg == "-i":
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
