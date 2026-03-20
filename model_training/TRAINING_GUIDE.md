# SMISDroid - Model Training Guide

## Quick Start

```bash
cd model_training

# Install dependencies
pip install -r requirements.txt

# Option A: TF-IDF + Dense NN (recommended — fast, small, 91%+ accuracy)
python train_fraud_model.py

# Option B: MobileBERT fine-tuning (slower, larger, 93-96% accuracy)
python train_mobilebert.py

# Verify the exported model
python evaluate_model.py
```

After training, the model files are automatically copied to `assets/`. Rebuild the app:
```bash
flutter build apk --debug
```

---

## Two Model Options

### Option A: TF-IDF + Dense Neural Network (Recommended)

| Aspect | Value |
|--------|-------|
| Script | `train_fraud_model.py` |
| Model Size | ~50-200 KB |
| Inference Time | ~15ms |
| Accuracy | 91%+ |
| Training Time | 2-5 min (CPU) |
| GPU Required | No |

**Architecture:**
```
Text → TF-IDF (5000 features, unigram+bigram) → Dense(256) → Dropout(0.3) → Dense(64) → Dropout(0.2) → Dense(1, sigmoid)
```

**Best for:** Production use. Small APK, fast inference, works well on low-end devices.

### Option B: MobileBERT Fine-Tuning

| Aspect | Value |
|--------|-------|
| Script | `train_mobilebert.py` |
| Model Size | ~25 MB (quantized) |
| Inference Time | ~50ms |
| Accuracy | 93-96% |
| Training Time | 30-60 min (GPU), 3-5 hours (CPU) |
| GPU Required | Recommended |

**Architecture:**
```
Text → MobileBERT Tokenizer (128 tokens) → MobileBERT Encoder → Classification Head → Softmax → Fraud Probability
```

**Best for:** Maximum accuracy. Understands context, word order, and novel fraud patterns better than TF-IDF.

---

## Dataset Setup

### Automatic (Default)

The training scripts will:
1. Try to download UCI SMS Spam dataset via `kagglehub`
2. Load any CSV data you place in `datasets/`
3. Always generate 1,200 synthetic Indian financial fraud samples

### Manual Dataset Setup

Place CSV files in `model_training/datasets/` with columns `text` and `label`:

```csv
text,label
"Your account is blocked verify at http://fake.tk",1
"Dear Customer Rs.5000 debited from A/c. -SBI",0
```

- `label=1` → Fraud/Spam
- `label=0` → Legitimate/Ham

**Supported files:**

| File | Format | Source |
|------|--------|--------|
| `uci_sms_spam.csv` | `v1` (ham/spam), `v2` (text) | [UCI ML Repository](https://archive.ics.uci.edu/dataset/228/sms+spam+collection) |
| `mendeley_smishing.csv` | `TEXT`, `LABEL` | [Mendeley Data](https://data.mendeley.com/datasets) |
| `indian_fraud_sms.csv` | `text`, `label` | Your own collection |

### Download UCI Dataset Manually

If `kagglehub` doesn't work:
1. Go to https://www.kaggle.com/datasets/uciml/sms-spam-collection-dataset
2. Download `spam.csv`
3. Save as `model_training/datasets/uci_sms_spam.csv`

---

## Training Pipeline (Step by Step)

### Step 1: Data Loading & Merging
- Loads all available CSVs from `datasets/`
- Generates 1,200 synthetic Indian fraud samples (templates × random params)
- Deduplicates and shuffles
- Reports class distribution

### Step 2: Text Preprocessing
```
Original: "URGENT: Your HDFC account blocked! Verify at http://hdfc-verify.tk"
Cleaned:  "urgent your hdfc account blocked verify at URL"
```
- Lowercase
- Replace URLs with `URL` token
- Remove special characters
- Normalize whitespace

### Step 3: Feature Extraction

**TF-IDF model:** 5,000-dimensional sparse vector (unigrams + bigrams)
**MobileBERT:** 128-token sequence of WordPiece token IDs

### Step 4: Model Training

**TF-IDF:** 15 epochs, batch size 32, Adam optimizer (lr=0.001), class weight 1.5x for fraud
**MobileBERT:** 3 epochs, batch size 16, Adam optimizer (lr=2e-5)

### Step 5: Evaluation
- Classification report (precision, recall, F1)
- Confusion matrix (TP, TN, FP, FN)

### Step 6: TFLite Export
- Float16 quantization (TF-IDF) or dynamic range quantization (MobileBERT)
- Vocabulary exported as JSON
- Config exported as JSON

### Step 7: Verification
- Runs inference on test set using the TFLite model
- Reports accuracy to verify conversion didn't degrade performance

### Step 8: Asset Copy
- Copies `fraud_model.tflite` → `assets/models/`
- Copies `vocabulary.json` → `assets/nlp/`
- Copies `nlp_config.json` → `assets/nlp/`
- Copies `model_weights.json` → `assets/nlp/`

---

## Output Files

After training, these files are generated:

| File | Location | Purpose |
|------|----------|---------|
| `fraud_model.tflite` | `assets/models/` | TFLite model for on-device inference |
| `vocabulary.json` | `assets/nlp/` | Word → token index mapping |
| `nlp_config.json` | `assets/nlp/` | Model configuration for Dart |
| `model_weights.json` | `assets/nlp/` | Model metadata |

---

## How Dart Uses the Model

The `NlpClassifier` in `lib/nlp/nlp_classifier.dart`:

1. Loads `fraud_model.tflite` via `tflite_flutter`
2. Loads `vocabulary.json` as `Map<String, int>`
3. For each message:
   - Tokenizes text using vocabulary
   - Creates input tensor (padded to 128)
   - Runs `Interpreter.run()`
   - Returns fraud probability (0.0-1.0)
4. Falls back to keyword scoring if model fails

---

## Google Colab Setup

If you don't have a local GPU:

```python
# In Colab notebook:
!git clone https://github.com/yourusername/smisdroid.git
%cd smisdroid/model_training
!pip install -r requirements.txt

# Download dataset (or upload your own)
!kaggle datasets download -d uciml/sms-spam-collection-dataset -p datasets/
!unzip datasets/sms-spam-collection-dataset.zip -d datasets/
!mv datasets/spam.csv datasets/uci_sms_spam.csv

# Train
!python train_mobilebert.py  # or train_fraud_model.py

# Download the trained model
from google.colab import files
files.download('flutter_assets/fraud_model.tflite')
files.download('flutter_assets/vocabulary.json')
files.download('flutter_assets/nlp_config.json')
```

Then copy the downloaded files to your local `assets/` directory.

---

## Troubleshooting

### "No training data available!"
Place at least one dataset CSV in `model_training/datasets/`, or the script will use only synthetic data (1,200 samples). For best results, use the UCI dataset (5,574 samples).

### "ModuleNotFoundError: No module named 'tensorflow'"
```bash
pip install tensorflow>=2.14.0
```

### "Out of memory during MobileBERT training"
- Reduce `BATCH_SIZE` to 8
- Use `train_fraud_model.py` instead (TF-IDF model uses much less memory)
- Use Google Colab with GPU

### "TFLite conversion failed"
- Ensure TensorFlow >= 2.14.0
- For MobileBERT, the `SELECT_TF_OPS` flag is needed (already set)

### "Model accuracy is low (<80%)"
- Add more training data, especially Indian financial fraud samples
- Increase `EPOCHS` (try 20-30 for TF-IDF, 5 for MobileBERT)
- Check class balance (should be ~40-60% fraud)
