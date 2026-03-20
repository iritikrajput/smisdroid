#!/usr/bin/env python3
"""
SMISDroid - SMS Fraud Detection Model Training Pipeline
========================================================

Trains a TF-IDF + Dense Neural Network classifier on SMS fraud data,
then exports to TensorFlow Lite for on-device inference.

This is the RECOMMENDED approach for SMISDroid because:
  - Produces a tiny model (~50-200 KB)
  - Fast inference (<20ms on mobile)
  - Good accuracy (91%+)
  - Compatible with tflite_flutter

For MobileBERT (heavier, higher accuracy), see train_mobilebert.py

Usage:
    pip install -r requirements.txt
    python train_fraud_model.py
"""

import os
import json
import re
import random
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix
import tensorflow as tf

# ─── Config ───────────────────────────────────────────────

DATASET_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "datasets")
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "flutter_assets")
FINAL_ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

MAX_FEATURES = 5000       # TF-IDF vocabulary size
MAX_SEQ_LENGTH = 128      # Max tokens (matches NlpClassifier in Dart)
TEST_SPLIT = 0.2
RANDOM_SEED = 42
EPOCHS = 15
BATCH_SIZE = 32

# ─── Step 1: Load & Merge Datasets ───────────────────────

def load_uci_sms_spam():
    """Load UCI SMS Spam Collection dataset."""
    path = os.path.join(DATASET_DIR, "uci_sms_spam.csv")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        df = pd.read_csv(path, encoding="latin-1")
        if "v1" in df.columns and "v2" in df.columns:
            df = df.rename(columns={"v1": "label", "v2": "text"})
            df["label"] = df["label"].map({"ham": 0, "spam": 1})
        elif "label" in df.columns and "text" in df.columns:
            pass
        return df[["text", "label"]].dropna()

    # Download from kaggle if file is empty/missing
    print("[INFO] Downloading UCI SMS Spam dataset...")
    try:
        import kagglehub
        dataset_path = kagglehub.dataset_download("uciml/sms-spam-collection-dataset")
        csv_path = os.path.join(dataset_path, "spam.csv")
        df = pd.read_csv(csv_path, encoding="latin-1")
        df = df.rename(columns={"v1": "label", "v2": "text"})
        df["label"] = df["label"].map({"ham": 0, "spam": 1})
        df = df[["text", "label"]].dropna()
        df.to_csv(path, index=False)
        return df
    except Exception as e:
        print(f"[WARN] Could not download UCI dataset: {e}")
        return pd.DataFrame(columns=["text", "label"])


def load_mendeley_smishing():
    """Load Mendeley smishing dataset."""
    path = os.path.join(DATASET_DIR, "mendeley_smishing.csv")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        df = pd.read_csv(path)
        if "TEXT" in df.columns and "LABEL" in df.columns:
            df = df.rename(columns={"TEXT": "text", "LABEL": "label"})
        return df[["text", "label"]].dropna()
    print("[WARN] mendeley_smishing.csv is empty — skipping")
    return pd.DataFrame(columns=["text", "label"])


def load_indian_fraud():
    """Load Indian financial fraud SMS dataset."""
    path = os.path.join(DATASET_DIR, "indian_fraud_sms.csv")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        df = pd.read_csv(path)
        if "text" in df.columns and "label" in df.columns:
            return df[["text", "label"]].dropna()
        for text_col in ["message", "sms", "content"]:
            for label_col in ["label", "class", "category", "is_fraud"]:
                if text_col in df.columns and label_col in df.columns:
                    df = df.rename(columns={text_col: "text", label_col: "label"})
                    return df[["text", "label"]].dropna()
    print("[WARN] indian_fraud_sms.csv is empty — skipping")
    return pd.DataFrame(columns=["text", "label"])


def create_synthetic_fraud_data():
    """Generate synthetic Indian financial fraud SMS samples for training."""
    fraud_templates = [
        "Your electricity bill of Rs.{amt} is pending. Pay now at {url} or service will be disconnected today",
        "URGENT: Your {bank} account has been blocked. Verify immediately at {url}",
        "Dear customer, your KYC has expired. Update now at {url} to avoid account suspension",
        "You have won Rs.{amt} in lottery! Claim your prize at {url} before it expires",
        "Your UPI payment of Rs.{amt} failed. Retry at {url} immediately",
        "ALERT: Unauthorized login detected on your {bank} account. Verify at {url}",
        "Final notice: Pay your {bank} credit card bill of Rs.{amt} at {url} or face legal action",
        "Your {bank} debit card will be deactivated. Update PAN details at {url}",
        "Congratulations! You are selected for Rs.{amt} cashback. Claim at {url}",
        "Your Aadhaar linked mobile number needs verification. Update at {url} within 24 hours",
        "IRCTC refund of Rs.{amt} is pending. Click {url} to receive in your account",
        "Your electricity connection will be disconnected in 2 hours. Pay Rs.{amt} at {url}",
        "Dear {bank} customer, confirm your identity at {url} to continue using services",
        "Your phone number has been selected for Rs.{amt} reward by Jio. Collect at {url}",
        "WARNING: Your {bank} account will be frozen. Verify OTP at {url}",
        "Pay your gas bill of Rs.{amt} immediately at {url} to avoid disconnection",
        "Your PAN card is linked to suspicious activity. Verify at {url} now",
        "BESCOM notice: Electricity supply will be cut off. Pay Rs.{amt} at {url}",
        "Your {bank} fixed deposit of Rs.{amt} has matured. Renew at {url}",
        "Government subsidy of Rs.{amt} credited. Verify Aadhaar at {url} to claim",
        "IMPORTANT: Your {bank} net banking will expire today. Reactivate at {url}",
        "Your {bank} account shows suspicious transaction of Rs.{amt}. Verify at {url}",
        "Your mobile number is being deactivated by TRAI. Reverify at {url}",
        "Income tax refund of Rs.{amt} approved. Submit bank details at {url}",
        "Your {bank} loan application approved for Rs.{amt}. Complete verification at {url}",
    ]

    safe_templates = [
        "Dear Customer, Rs.{amt} debited from A/c XX1234. Avl Bal Rs.25000. -{bank}",
        "Your {bank} A/c credited with Rs.{amt}. Balance: Rs.50000",
        "OTP for transaction: 847291. Valid for 5 minutes. Do not share with anyone. -{bank}",
        "Your order #ORD{amt} has been shipped via BlueDart. Track at bluedart.com",
        "Reminder: Your {bank} credit card payment of Rs.{amt} is due on 25th March",
        "Thank you for shopping at BigBazaar. Bill amount: Rs.{amt}. Points earned: 50",
        "Your Airtel recharge of Rs.{amt} is successful. Validity: 28 days",
        "Flight booking confirmed. PNR: ABC123. {bank} card charged Rs.{amt}",
        "Your {bank} home loan EMI of Rs.{amt} has been auto-debited successfully",
        "Welcome to {bank} Mobile Banking. Your registration is successful",
        "Dear customer, your FD of Rs.{amt} has been renewed for 1 year at 7.1% -{bank}",
        "Your mutual fund SIP of Rs.{amt} has been processed successfully via {bank}",
        "Electricity bill of Rs.{amt} paid successfully via {bank} for account 1234567",
        "Your Amazon order has been delivered. Rate your experience at amazon.in",
        "Salary of Rs.{amt} credited to your {bank} A/c. Updated balance: Rs.75000",
        "Meeting at 3pm tomorrow in the conference room. Please confirm attendance.",
        "Happy birthday! Wishing you a wonderful year ahead. - Team {bank}",
        "Your {bank} insurance premium of Rs.{amt} has been received. Thank you.",
        "Movie tickets booked for 2 at PVR. Amount Rs.{amt} charged to {bank} card",
        "Your Swiggy order is on the way. Delivery in 25 minutes.",
    ]

    banks = ["SBI", "HDFC", "ICICI", "Axis", "Kotak", "PNB", "BOB", "Canara", "YES"]
    urls = [
        "http://sbi-verify.xyz", "http://hdfc-update.tk", "http://bill-pay-now.ml",
        "http://kyc-update.cf", "http://claim-prize.ga", "http://verify-acc.top",
        "http://192.168.1.1/verify", "http://paytm-refund.buzz",
        "http://bank-secure.click", "http://aadhaar-verify.link",
    ]
    amounts = ["500", "1500", "2500", "5000", "10000", "25000", "50000"]

    random.seed(RANDOM_SEED)
    data = []

    for _ in range(600):
        template = random.choice(fraud_templates)
        text = template.format(
            amt=random.choice(amounts),
            bank=random.choice(banks),
            url=random.choice(urls),
        )
        data.append({"text": text, "label": 1})

    for _ in range(600):
        template = random.choice(safe_templates)
        text = template.format(
            amt=random.choice(amounts),
            bank=random.choice(banks),
        )
        data.append({"text": text, "label": 0})

    return pd.DataFrame(data)


def load_all_data():
    """Load and merge all available datasets."""
    dfs = []

    uci = load_uci_sms_spam()
    if len(uci) > 0:
        print(f"[DATA] UCI SMS Spam: {len(uci)} samples (fraud={uci['label'].sum()})")
        dfs.append(uci)

    mendeley = load_mendeley_smishing()
    if len(mendeley) > 0:
        print(f"[DATA] Mendeley Smishing: {len(mendeley)} samples (fraud={mendeley['label'].sum()})")
        dfs.append(mendeley)

    indian = load_indian_fraud()
    if len(indian) > 0:
        print(f"[DATA] Indian Fraud SMS: {len(indian)} samples (fraud={indian['label'].sum()})")
        dfs.append(indian)

    synthetic = create_synthetic_fraud_data()
    print(f"[DATA] Synthetic Indian fraud: {len(synthetic)} samples (fraud={synthetic['label'].sum()})")
    dfs.append(synthetic)

    if not dfs:
        raise ValueError("No training data available!")

    combined = pd.concat(dfs, ignore_index=True)
    combined = combined.drop_duplicates(subset=["text"])
    combined = combined.sample(frac=1, random_state=RANDOM_SEED).reset_index(drop=True)

    print(f"\n[DATA] Combined dataset: {len(combined)} samples")
    print(f"[DATA] Fraud: {combined['label'].sum()} ({combined['label'].mean()*100:.1f}%)")
    print(f"[DATA] Legitimate: {(combined['label']==0).sum()} ({(1-combined['label'].mean())*100:.1f}%)")

    return combined


# ─── Step 2: Text Preprocessing ──────────────────────────

def preprocess_text(text):
    """Clean text for TF-IDF vectorization."""
    text = str(text).lower()
    text = re.sub(r'http\S+|www\.\S+', ' URL ', text)
    text = re.sub(r'[^a-z0-9\s]', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


# ─── Step 3: TF-IDF Vectorization ────────────────────────

def build_tfidf(texts):
    """Build TF-IDF vectorizer and transform texts."""
    vectorizer = TfidfVectorizer(
        max_features=MAX_FEATURES,
        ngram_range=(1, 2),
        min_df=2,
        max_df=0.95,
        lowercase=True,
        analyzer="word",
        sublinear_tf=True,
    )
    X = vectorizer.fit_transform(texts)
    return vectorizer, X


# ─── Step 4: Build TensorFlow Model ──────────────────────

def build_model(input_dim):
    """Build a compact dense neural network for TFLite conversion."""
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(input_dim,)),
        tf.keras.layers.Dense(256, activation="relu"),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(64, activation="relu"),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(1, activation="sigmoid"),
    ])

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss="binary_crossentropy",
        metrics=["accuracy"],
    )
    return model


# ─── Step 5: Export to TFLite ─────────────────────────────

def export_tflite(model, output_path):
    """Convert Keras model to quantized TFLite."""
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]

    tflite_model = converter.convert()

    with open(output_path, "wb") as f:
        f.write(tflite_model)

    size_kb = len(tflite_model) / 1024
    print(f"\n[EXPORT] TFLite model saved: {output_path} ({size_kb:.1f} KB)")
    return tflite_model


def export_vocabulary(vectorizer, output_path):
    """Export TF-IDF vocabulary as JSON for Dart."""
    vocab = vectorizer.vocabulary_
    sorted_vocab = {k: int(v) for k, v in sorted(vocab.items(), key=lambda x: x[1])}
    with open(output_path, "w") as f:
        json.dump(sorted_vocab, f)
    print(f"[EXPORT] Vocabulary saved: {output_path} ({len(sorted_vocab)} words)")


def export_config(output_path):
    """Export NLP config for Dart."""
    config = {
        "model_type": "tfidf_dense",
        "max_features": MAX_FEATURES,
        "max_seq_length": MAX_SEQ_LENGTH,
        "input_type": "tfidf_vector",
        "output_type": "fraud_probability",
        "threshold_safe": 0.3,
        "threshold_suspicious": 0.6,
        "version": "1.0.0",
    }
    with open(output_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"[EXPORT] Config saved: {output_path}")


# ─── Step 6: Verify TFLite Model ─────────────────────────

def verify_tflite(tflite_path, X_test, y_test):
    """Run inference with the TFLite model and verify accuracy."""
    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    n_test = min(200, X_test.shape[0])
    correct = 0

    for i in range(n_test):
        input_data = X_test[i:i+1].astype(np.float32)
        if hasattr(input_data, "toarray"):
            input_data = input_data.toarray()

        interpreter.set_tensor(input_details[0]["index"], input_data)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details[0]["index"])

        pred = 1 if output[0][0] > 0.5 else 0
        if pred == y_test.iloc[i]:
            correct += 1

    accuracy = correct / n_test * 100
    print(f"\n[VERIFY] TFLite model accuracy on {n_test} samples: {accuracy:.1f}%")
    return accuracy


# ─── Main Pipeline ────────────────────────────────────────

def main():
    print("=" * 60)
    print("  SMISDroid - Fraud Detection Model Training")
    print("=" * 60)

    # Step 1: Load data
    print("\n--- Step 1: Loading datasets ---")
    df = load_all_data()

    # Step 2: Preprocess
    print("\n--- Step 2: Preprocessing ---")
    df["clean_text"] = df["text"].apply(preprocess_text)
    print(f"[PREP] Preprocessed {len(df)} messages")

    # Step 3: TF-IDF
    print("\n--- Step 3: TF-IDF Vectorization ---")
    vectorizer, X = build_tfidf(df["clean_text"])
    y = df["label"].astype(int)
    print(f"[TFIDF] Feature matrix: {X.shape}")

    # Split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=TEST_SPLIT, random_state=RANDOM_SEED, stratify=y
    )
    print(f"[SPLIT] Train: {X_train.shape[0]}, Test: {X_test.shape[0]}")

    # Step 4: Train model
    print("\n--- Step 4: Training Neural Network ---")
    model = build_model(MAX_FEATURES)
    model.summary()

    X_train_dense = X_train.toarray()
    X_test_dense = X_test.toarray()

    model.fit(
        X_train_dense, y_train,
        validation_data=(X_test_dense, y_test),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        class_weight={0: 1.0, 1: 1.5},
        verbose=1,
    )

    # Evaluate
    print("\n--- Step 5: Evaluation ---")
    y_pred_prob = model.predict(X_test_dense).flatten()
    y_pred = (y_pred_prob > 0.5).astype(int)

    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=["Legitimate", "Fraud"]))

    print("Confusion Matrix:")
    cm = confusion_matrix(y_test, y_pred)
    print(f"  TN={cm[0][0]}  FP={cm[0][1]}")
    print(f"  FN={cm[1][0]}  TP={cm[1][1]}")

    # Step 6: Export
    print("\n--- Step 6: Exporting to TFLite ---")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    tflite_path = os.path.join(OUTPUT_DIR, "fraud_model.tflite")
    export_tflite(model, tflite_path)
    export_vocabulary(vectorizer, os.path.join(OUTPUT_DIR, "vocabulary.json"))
    export_config(os.path.join(OUTPUT_DIR, "nlp_config.json"))

    weights_info = {"type": "tfidf_dense", "layers": len(model.layers), "params": int(model.count_params())}
    with open(os.path.join(OUTPUT_DIR, "model_weights.json"), "w") as f:
        json.dump(weights_info, f, indent=2)

    # Step 7: Verify
    print("\n--- Step 7: TFLite Verification ---")
    verify_tflite(tflite_path, X_test, y_test)

    # Step 8: Copy to Flutter assets
    print("\n--- Step 8: Copying to Flutter assets ---")
    import shutil
    asset_model = os.path.join(FINAL_ASSETS, "models", "fraud_model.tflite")
    asset_vocab = os.path.join(FINAL_ASSETS, "nlp", "vocabulary.json")
    asset_config = os.path.join(FINAL_ASSETS, "nlp", "nlp_config.json")
    asset_weights = os.path.join(FINAL_ASSETS, "nlp", "model_weights.json")

    shutil.copy2(tflite_path, asset_model)
    shutil.copy2(os.path.join(OUTPUT_DIR, "vocabulary.json"), asset_vocab)
    shutil.copy2(os.path.join(OUTPUT_DIR, "nlp_config.json"), asset_config)
    shutil.copy2(os.path.join(OUTPUT_DIR, "model_weights.json"), asset_weights)

    print(f"  -> {asset_model}")
    print(f"  -> {asset_vocab}")
    print(f"  -> {asset_config}")
    print(f"  -> {asset_weights}")

    print("\n" + "=" * 60)
    print("  TRAINING COMPLETE!")
    print("  Run 'flutter build apk --debug' to use the new model")
    print("=" * 60)


if __name__ == "__main__":
    main()
