#!/usr/bin/env python3
"""
SMISDroid - Model Evaluation & Testing
=======================================

Tests the exported TFLite model against sample messages.
Run this after training to verify the model works correctly.

Usage:
    python evaluate_model.py
"""

import os
import json
import numpy as np
import tensorflow as tf

ASSETS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
MODEL_PATH = os.path.join(ASSETS_DIR, "models", "fraud_model.tflite")
VOCAB_PATH = os.path.join(ASSETS_DIR, "nlp", "vocabulary.json")
CONFIG_PATH = os.path.join(ASSETS_DIR, "nlp", "nlp_config.json")

# Test messages with expected labels
TEST_CASES = [
    # (message, expected_label, description)
    ("Your electricity bill of Rs.2500 is pending. Pay now at http://bill-pay.xyz or disconnection today", 1, "Electricity scam"),
    ("URGENT: Your HDFC account has been blocked. Verify immediately at http://hdfc-verify.tk", 1, "Banking phishing"),
    ("Dear customer, your KYC has expired. Update now at http://kyc-update.cf", 1, "KYC scam"),
    ("You have won Rs.50000 in lottery! Claim your prize at http://claim-prize.ga", 1, "Lottery scam"),
    ("Your UPI payment of Rs.5000 failed. Retry at http://upi-retry.ml immediately", 1, "UPI fraud"),
    ("WARNING: Your SBI account will be frozen. Verify OTP at http://sbi-verify.xyz", 1, "Account freeze scam"),
    ("Dear Customer, Rs.5000 debited from A/c XX1234. Avl Bal Rs.25000. -ICICI", 0, "Legitimate debit alert"),
    ("Your HDFC A/c credited with Rs.25000. Balance: Rs.50000", 0, "Legitimate credit alert"),
    ("OTP for transaction: 847291. Valid for 5 minutes. Do not share. -SBI", 0, "Legitimate OTP"),
    ("Your order has been shipped via BlueDart. Track at bluedart.com", 0, "Legitimate shipping"),
    ("Meeting at 3pm tomorrow in the conference room", 0, "Normal message"),
    ("Happy birthday! Wishing you a wonderful year ahead", 0, "Personal message"),
    ("Your Airtel recharge of Rs.199 is successful. Validity: 28 days", 0, "Legitimate recharge"),
    ("Salary of Rs.50000 credited to your HDFC A/c. Updated balance: Rs.75000", 0, "Legitimate salary"),
]


def load_model():
    """Load TFLite model."""
    if not os.path.exists(MODEL_PATH) or os.path.getsize(MODEL_PATH) == 0:
        print(f"[ERROR] Model not found or empty: {MODEL_PATH}")
        print("Run train_fraud_model.py first!")
        return None

    interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
    interpreter.allocate_tensors()
    return interpreter


def load_vocab():
    """Load vocabulary."""
    if not os.path.exists(VOCAB_PATH) or os.path.getsize(VOCAB_PATH) == 0:
        print(f"[ERROR] Vocabulary not found or empty: {VOCAB_PATH}")
        return None

    with open(VOCAB_PATH, "r") as f:
        return json.load(f)


def load_config():
    """Load NLP config."""
    if not os.path.exists(CONFIG_PATH) or os.path.getsize(CONFIG_PATH) == 0:
        return {"model_type": "unknown", "max_features": 5000}

    with open(CONFIG_PATH, "r") as f:
        return json.load(f)


def preprocess_and_vectorize(text, vocab, max_features):
    """Preprocess text and convert to TF-IDF-like vector."""
    import re
    text = text.lower()
    text = re.sub(r'http\S+|www\.\S+', ' url ', text)
    text = re.sub(r'[^a-z0-9\s]', ' ', text)
    tokens = text.split()

    # Create feature vector (binary TF-IDF)
    features = np.zeros(max_features, dtype=np.float32)
    for token in tokens:
        if token in vocab:
            idx = vocab[token]
            if idx < max_features:
                features[idx] = 1.0

    # Also check bigrams
    for i in range(len(tokens) - 1):
        bigram = f"{tokens[i]} {tokens[i+1]}"
        if bigram in vocab:
            idx = vocab[bigram]
            if idx < max_features:
                features[idx] = 1.0

    return features.reshape(1, -1)


def run_inference(interpreter, input_data):
    """Run TFLite inference."""
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])
    return output[0][0]


def main():
    print("=" * 60)
    print("  SMISDroid - Model Evaluation")
    print("=" * 60)

    # Load model
    interpreter = load_model()
    if interpreter is None:
        return

    vocab = load_vocab()
    if vocab is None:
        return

    config = load_config()
    max_features = config.get("max_features", 5000)

    model_size = os.path.getsize(MODEL_PATH) / 1024
    print(f"\n[MODEL] Type: {config.get('model_type', 'unknown')}")
    print(f"[MODEL] Size: {model_size:.1f} KB")
    print(f"[MODEL] Vocabulary: {len(vocab)} tokens")
    print(f"[MODEL] Max features: {max_features}")

    # Run tests
    print(f"\n--- Testing {len(TEST_CASES)} messages ---\n")
    correct = 0
    results = []

    print(f"{'#':<3} {'Score':>6} {'Pred':>6} {'Exp':>5} {'OK':>3}  Description")
    print("-" * 60)

    for i, (message, expected, desc) in enumerate(TEST_CASES):
        input_data = preprocess_and_vectorize(message, vocab, max_features)
        score = run_inference(interpreter, input_data)

        predicted = 1 if score > 0.5 else 0
        is_correct = predicted == expected
        if is_correct:
            correct += 1

        label = "FRAUD" if predicted == 1 else "SAFE"
        check = "Y" if is_correct else "X"

        print(f"{i+1:<3} {score:>6.3f} {label:>6} {'F' if expected else 'S':>5} {check:>3}  {desc}")
        results.append({"score": float(score), "predicted": predicted, "expected": expected, "correct": is_correct})

    accuracy = correct / len(TEST_CASES) * 100
    print(f"\n{'=' * 60}")
    print(f"  Accuracy: {correct}/{len(TEST_CASES)} ({accuracy:.1f}%)")

    fraud_cases = [r for r in results if r["expected"] == 1]
    safe_cases = [r for r in results if r["expected"] == 0]

    fraud_correct = sum(1 for r in fraud_cases if r["correct"])
    safe_correct = sum(1 for r in safe_cases if r["correct"])

    print(f"  Fraud detection: {fraud_correct}/{len(fraud_cases)}")
    print(f"  Safe detection:  {safe_correct}/{len(safe_cases)}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
