# MobileBERT-Based SMS Fraud Detection Model

# Technical Report — Model Training & Evaluation

---

**Project:** SMISDroid — Secure-SMS Edge Defense
**Document Type:** Model Training Report
**Version:** 1.0
**Date:** March 21, 2026
**Prepared By:** SMISDroid Development Team
**Status:** Production Deployed

---

## Abstract

This document presents the complete training methodology, evaluation, and deployment pipeline for a fine-tuned MobileBERT model designed to classify SMS messages as either legitimate or fraudulent in real time on mobile devices. The model was trained on a curated dataset of 6,739 Indian financial SMS messages spanning six categories, achieving a test accuracy of 99.70%, precision of 99.87%, recall of 99.61%, and an F1-score of 99.74% on a held-out test set of 1,348 messages. The trained model is exported as a quantized TensorFlow Lite file (25.5 MB) for on-device inference within the SMISDroid Android application, operating entirely without cloud connectivity.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Model Selection and Justification](#2-model-selection-and-justification)
3. [Model Architecture](#3-model-architecture)
4. [Dataset Description](#4-dataset-description)
5. [Data Preprocessing and Tokenization](#5-data-preprocessing-and-tokenization)
6. [Training Methodology](#6-training-methodology)
7. [Evaluation Results](#7-evaluation-results)
8. [Error Analysis](#8-error-analysis)
9. [Model Export and Quantization](#9-model-export-and-quantization)
10. [Deployment and On-Device Integration](#10-deployment-and-on-device-integration)
11. [Reproducibility](#11-reproducibility)
12. [Limitations](#12-limitations)
13. [Conclusion and Future Work](#13-conclusion-and-future-work)
14. [References](#14-references)
15. [Appendix](#15-appendix)

---

## 1. Introduction

### 1.1 Problem Statement

SMS-based financial fraud (smishing) continues to be a significant threat to mobile users in India, with attackers impersonating banks, utility providers, and government agencies to extract sensitive information or redirect victims to phishing portals. Traditional cloud-based detection systems introduce privacy risks, require internet connectivity, and suffer from latency that allows users to interact with malicious content before a warning arrives.

### 1.2 Objective

The objective of this work is to train a lightweight, high-accuracy natural language processing (NLP) model capable of classifying incoming SMS messages as fraudulent or legitimate entirely on-device, with the following requirements:

- Binary classification: Fraud (1) vs. Legitimate (0)
- Inference latency under 100 milliseconds on a mid-range Android device
- No network dependency for inference
- Compatibility with TensorFlow Lite runtime
- Integration as Tier 1 (NLP) of the SMISDroid three-tier detection pipeline

### 1.3 Approach

We adopt a **transfer learning** approach, fine-tuning a pre-trained MobileBERT model on a domain-specific dataset of Indian financial SMS messages. The fine-tuned model is then converted to TensorFlow Lite format with dynamic range quantization for efficient on-device deployment.

---

## 2. Model Selection and Justification

### 2.1 Candidate Models Considered

| Model | Parameters | Size | Inference Speed | Accuracy (General NLU) |
|-------|-----------|------|-----------------|----------------------|
| BERT-base | 110M | ~440 MB | ~300ms | Baseline |
| DistilBERT | 66M | ~260 MB | ~180ms | 97% of BERT |
| ALBERT | 12M | ~50 MB | ~200ms | 95% of BERT |
| **MobileBERT** | **25M** | **~100 MB** | **~60ms** | **96% of BERT** |
| TinyBERT | 14.5M | ~60 MB | ~80ms | 93% of BERT |

### 2.2 Rationale for MobileBERT

MobileBERT (Sun et al., 2020) was selected for the following reasons:

1. **Mobile-optimized architecture.** MobileBERT employs a bottleneck structure that reduces hidden dimensions from 512 to 128 between transformer layers, achieving a 4.3x reduction in model size compared to BERT-base while retaining 96% of its performance on NLU benchmarks.

2. **TFLite compatibility.** MobileBERT was specifically designed for TensorFlow Lite conversion, ensuring stable and efficient on-device inference without custom operators.

3. **Inference speed.** At approximately 40–60ms per inference on mid-range mobile hardware, MobileBERT meets the sub-100ms latency requirement for real-time SMS analysis.

4. **Pre-training quality.** MobileBERT is pre-trained on English Wikipedia and BooksCorpus using both Masked Language Modeling (MLM) and Next Sentence Prediction (NSP) objectives, providing strong linguistic foundations for downstream text classification.

5. **Proven track record.** MobileBERT has been widely adopted in production mobile applications for text classification, sentiment analysis, and question answering tasks.

---

## 3. Model Architecture

### 3.1 Base Architecture Overview

MobileBERT follows the transformer encoder architecture with a bottleneck design that reduces computational cost while maintaining representational capacity.

```
Input SMS Text
       │
       ▼
┌──────────────────────────────────────┐
│  WordPiece Tokenizer                 │
│  Vocabulary: 30,522 tokens           │
│  Max Sequence Length: 128 tokens     │
│  Output: input_ids, attention_mask,  │
│          token_type_ids              │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  Embedding Layer                     │
│  Token Embedding (128-dim)           │
│  + Position Embedding (128-dim)      │
│  + Segment Embedding (128-dim)       │
│  Output: [batch, 128, 128]           │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  MobileBERT Encoder (×24 layers)     │
│                                      │
│  Each layer:                         │
│  ┌────────────────────────────────┐  │
│  │ Bottleneck Input  (128-dim)    │  │
│  │        ↓                       │  │
│  │ Multi-Head Self-Attention      │  │
│  │ (4 heads, 128-dim)             │  │
│  │        ↓                       │  │
│  │ Feed-Forward Network           │  │
│  │ (128 → 512 → 128)             │  │
│  │        ↓                       │  │
│  │ Bottleneck Output (128-dim)    │  │
│  └────────────────────────────────┘  │
│  Output: [batch, 128, 128]           │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  [CLS] Token Extraction              │
│  Extracts first token representation │
│  Output: [batch, 128]                │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│  Classification Head (Fine-tuned)    │
│  Dense(128 → 2)                      │
│  Softmax Activation                  │
│  Output: [P(legitimate), P(fraud)]   │
└──────────────────┬───────────────────┘
                   │
                   ▼
         Fraud Probability (0.0 – 1.0)
```

### 3.2 Architectural Specifications

| Component | Value |
|-----------|-------|
| Transformer encoder layers | 24 |
| Hidden size (bottleneck) | 128 |
| Intermediate feed-forward size | 512 |
| Number of attention heads | 4 per layer |
| Embedding dimension | 128 |
| Bottleneck structure | Yes (128 → 512 → 128) |
| Activation function | GeLU |
| Dropout rate | 0.1 |
| Maximum position embeddings | 512 |
| Total trainable parameters | 24,582,914 |

### 3.3 Transfer Learning Strategy

| Component | Initialization | Training |
|-----------|---------------|----------|
| Embedding layers | Pre-trained (`google/mobilebert-uncased`) | Fine-tuned |
| 24 encoder layers | Pre-trained (`google/mobilebert-uncased`) | Fine-tuned |
| Classification head | Randomly initialized (`Dense(128 → 2)`) | Trained from scratch |

All layers are fine-tuned end-to-end without freezing, as the domain-specific nature of financial SMS benefits from full model adaptation.

---

## 4. Dataset Description

### 4.1 Data Source

The training data is sourced from `train.csv`, a curated dataset of Indian financial SMS messages. The dataset contains both legitimate banking and utility notifications as well as fraudulent messages spanning multiple scam categories common in the Indian financial ecosystem.

### 4.2 Raw Data Summary

| Property | Value |
|----------|-------|
| Source file | `train.csv` |
| Total raw rows | 7,001 (including header) |
| Columns | `message_text` (string), `class_label` (string) |
| Language | English (Indian financial context) |
| Valid rows after cleaning | 6,739 |

### 4.3 Original Label Distribution

The dataset contains six class labels. For binary classification, all non-benign classes are mapped to the fraud class (label = 1).

| Original Class Label | Sample Count | Percentage | Binary Mapping | Category Description |
|---------------------|-------------|------------|----------------|---------------------|
| `benign` | 2,923 | 43.4% | 0 (Legitimate) | Genuine bank transaction alerts, OTPs, delivery updates, bill confirmations, personal messages |
| `kyc_scam` | 809 | 12.0% | 1 (Fraud) | Fraudulent KYC update/verification requests directing to malicious portals |
| `impersonation` | 793 | 11.8% | 1 (Fraud) | Messages impersonating banks, electricity boards, or government agencies |
| `phishing_link` | 766 | 11.4% | 1 (Fraud) | Generic phishing messages containing malicious URLs |
| `fake_payment_portal` | 640 | 9.5% | 1 (Fraud) | Fake bill/payment portals impersonating utilities |
| `account_block_scam` | 328 | 4.9% | 1 (Fraud) | Account blocked/suspended/frozen scare messages |
| **Total** | **6,739** | **100%** | | |

### 4.4 Binary Class Distribution

| Class | Label | Count | Percentage |
|-------|-------|-------|------------|
| Legitimate | 0 | 2,923 | 43.4% |
| Fraud | 1 | 3,816 | 56.6% |
| **Total** | | **6,739** | **100%** |

The dataset exhibits a mild class imbalance (56.6% fraud vs 43.4% legitimate), which is within acceptable bounds and does not require oversampling or class weighting.

### 4.5 Data Cleaning Procedure

The following cleaning steps were applied in order:

1. **Column selection.** Retained only `message_text` and `class_label` columns.
2. **Null removal.** Dropped all rows where either column contained `NaN` values.
3. **Label validation.** Filtered rows to retain only the six valid class labels listed in Section 4.3. This removed approximately 261 rows containing malformed labels caused by multi-line message text spilling into the label column during CSV parsing.
4. **Binary label mapping.** Mapped `benign` → 0, all other labels → 1.
5. **Deduplication.** Removed exact duplicate messages based on text content.
6. **Shuffling.** Randomly shuffled the dataset with a fixed seed (42) for reproducibility.

### 4.6 Train/Test Split

| Split | Samples | Percentage | Fraud Count | Fraud Ratio | Legitimate Count | Legitimate Ratio |
|-------|---------|------------|------------|-------------|-----------------|-----------------|
| Training | 5,391 | 80% | 3,053 | 56.6% | 2,338 | 43.4% |
| Testing | 1,348 | 20% | 763 | 56.6% | 585 | 43.4% |
| **Total** | **6,739** | **100%** | **3,816** | **56.6%** | **2,923** | **43.4%** |

- **Split method:** Stratified random split using `sklearn.model_selection.train_test_split`
- **Stratification:** By binary label, ensuring identical fraud/legitimate ratios in both splits
- **Random seed:** 42
- **Data leakage verification:** Zero overlapping messages between train and test sets (independently verified post-split)

### 4.7 Representative Samples

**Fraud Messages:**

> BOI Security: Transaction of Rs.2135 from account 9787044552 is held. Verify identity at https://mahadiscom-7Sx9xA8B8.in/bill/pay to release.

> BWSSB Notice: Pending water bill Rs.20462 for consumer 0258513641. Pay online: https://axisbank-69ul4.in/confirm to avoid disconnection tomorrow.

**Legitimate Messages:**

> New water meter installation scheduled at your property on 3 Nov 2024. Be available 9 AM-1 PM.

> Your water account 5774836158 has no pending dues. Thank you for timely payment.

---

## 5. Data Preprocessing and Tokenization

### 5.1 Tokenizer Specifications

| Property | Value |
|----------|-------|
| Tokenizer class | `MobileBertTokenizer` (Hugging Face Transformers) |
| Pre-trained source | `google/mobilebert-uncased` |
| Algorithm | WordPiece (Wu et al., 2016) |
| Vocabulary size | 30,522 tokens |
| Case handling | Uncased (all input converted to lowercase) |
| `[CLS]` token ID | 101 |
| `[SEP]` token ID | 102 |
| `[PAD]` token ID | 0 |
| `[UNK]` token ID | 100 |

### 5.2 Tokenization Pipeline

The tokenization process converts raw SMS text into fixed-length integer sequences suitable for model input:

```
Step 1: Raw Input
  "Your HDFC account blocked. Verify at http://hdfc-verify.tk"

Step 2: Lowercasing (uncased model)
  "your hdfc account blocked. verify at http://hdfc-verify.tk"

Step 3: WordPiece Tokenization
  ["[CLS]", "your", "hd", "##fc", "account", "blocked", ".", "verify",
   "at", "http", ":", "/", "/", "hd", "##fc", "-", "verify", ".", "tk", "[SEP]"]

Step 4: Token ID Mapping
  [101, 2115, 16425, 8093, 4070, 2741, 1012, 20410,
   2012, 8299, 1024, 1013, 1013, 16425, 8093, 1011, 20410, 1012, 23095, 102]

Step 5: Padding to Max Length (128)
  [101, 2115, ..., 23095, 102, 0, 0, 0, ..., 0]  (128 total)
```

### 5.3 Input Tensor Format

Each tokenized message produces three input tensors:

| Tensor | Shape | Data Type | Description |
|--------|-------|-----------|-------------|
| `input_ids` | `[1, 128]` | int32 | WordPiece token indices |
| `attention_mask` | `[1, 128]` | int32 | 1 for real tokens, 0 for padding positions |
| `token_type_ids` | `[1, 128]` | int32 | All zeros (single-segment input) |

### 5.4 Sequence Length Handling

| Scenario | Action |
|----------|--------|
| Message < 128 tokens | Right-padded with `[PAD]` (ID=0) |
| Message > 128 tokens | Truncated from the right (tail tokens removed) |
| Typical SMS length | 20–60 tokens (well within 128 limit) |

A maximum sequence length of 128 tokens accommodates approximately 80–100 words, which is sufficient for the vast majority of SMS messages (standard SMS is limited to 160 characters).

---

## 6. Training Methodology

### 6.1 Training Hyperparameters

| Hyperparameter | Value | Rationale |
|---------------|-------|-----------|
| Number of epochs | 3 | Standard recommendation for BERT fine-tuning on small datasets (Devlin et al., 2019); prevents overfitting |
| Batch size | 16 | Standard for BERT fine-tuning; balances memory usage and gradient stability |
| Learning rate | 2 × 10⁻⁵ | Within the recommended range (2e-5 to 5e-5) for BERT fine-tuning (Devlin et al., 2019) |
| Optimizer | Adam (Kingma & Ba, 2015) | Standard optimizer for transformer models; adaptive learning rates per parameter |
| Loss function | Sparse Categorical Cross-Entropy (from logits) | Operates on raw model logits; numerically stable; supports integer labels |
| Weight initialization | Pre-trained (encoder) + Xavier random (classifier) | Transfer learning from pre-trained MobileBERT |
| Layer freezing | None | Full fine-tuning yields better results on domain-specific data |
| Learning rate warmup | None | Not required for 3-epoch fine-tuning on this dataset size |
| Gradient clipping | Default (handled by Adam optimizer) | Prevents gradient explosion |
| Random seed | 42 | Ensures reproducibility across runs |

### 6.2 Training Infrastructure

| Resource | Specification |
|----------|--------------|
| Processor | Intel CPU (AVX2, AVX_VNNI, FMA instruction sets) |
| GPU | NVIDIA GeForce RTX 2050 (available but not used; CUDA drivers not installed) |
| Training device | CPU |
| Framework | TensorFlow 2.21.0 |
| Transformers library | Hugging Face Transformers 4.x |
| Operating system | Kali Linux 6.18.12 |
| Total training time | ~30 minutes |
| Peak memory usage | ~4 GB RAM |

### 6.3 Training Data Pipeline

```
Raw Dataset (train.csv)
       │
       ▼
┌──────────────────────────────┐
│  Data Cleaning               │  7,001 → 6,739 valid rows
│  Binary Label Mapping        │  benign=0, all fraud types=1
│  Deduplication               │  Remove exact text duplicates
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Stratified Train/Test Split │  80% train (5,391 samples)
│  Random Seed = 42            │  20% test  (1,348 samples)
│  Preserves class ratios      │  Both: 56.6% fraud / 43.4% legit
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  WordPiece Tokenization      │  MobileBertTokenizer
│  Padding to 128 tokens       │  → input_ids [N, 128]
│  Attention mask generation   │  → attention_mask [N, 128]
│  Segment ID generation       │  → token_type_ids [N, 128]
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  TensorFlow Dataset Pipeline │  Shuffle (buffer=5,391)
│                              │  Batch (size=16)
│                              │  Prefetch (AUTOTUNE)
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Model Loading               │  google/mobilebert-uncased
│  + Classification Head Init  │  Dense(128 → 2), random init
│  Compile with Adam (2e-5)    │  SparseCCE loss + accuracy metric
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  Fine-tuning (3 Epochs)      │  337 batches/epoch = 1,011 steps
│  Validation after each epoch │  On held-out test set (1,348)
└──────────────┬───────────────┘
               │
               ▼
         Trained Model
```

### 6.4 Training Progress

| Epoch | Batches | Training Loss (Start → End) | Training Accuracy (Start → End) | Validation Accuracy |
|-------|---------|---------------------------|-------------------------------|---------------------|
| 1/3 | 337 | 242,531 → ~8,000 | 31.3% → 90.2% | ~95% |
| 2/3 | 337 | ~8,000 → ~200 | ~95% → 97.3% | ~98% |
| 3/3 | 337 | ~200 → ~112 | ~98% → **99.4%** | **99.7%** |

### 6.5 Training Computation Summary

| Metric | Value |
|--------|-------|
| Total training samples | 5,391 |
| Samples per batch | 16 |
| Batches per epoch | 337 (⌈5,391 ÷ 16⌉) |
| Total training steps | 1,011 (337 × 3) |
| Total parameter updates | 1,011 |
| Average time per step | ~1.8 seconds |
| Total training wall time | ~30 minutes |

---

## 7. Evaluation Results

### 7.1 Overall Performance Metrics

All metrics are computed on the held-out test set (1,348 samples, never seen during training).

| Metric | Value | Definition |
|--------|-------|------------|
| **Accuracy** | **99.70%** | (TP + TN) / Total = (760 + 584) / 1,348 |
| **Precision** | **99.87%** | TP / (TP + FP) = 760 / 761 |
| **Recall (Sensitivity)** | **99.61%** | TP / (TP + FN) = 760 / 763 |
| **F1-Score** | **99.74%** | 2 × (Precision × Recall) / (Precision + Recall) |
| **Specificity** | **99.83%** | TN / (TN + FP) = 584 / 585 |
| **False Positive Rate** | **0.17%** | FP / (FP + TN) = 1 / 585 |
| **False Negative Rate** | **0.39%** | FN / (FN + TP) = 3 / 763 |

### 7.2 Per-Class Classification Report

```
                  Precision    Recall    F1-Score    Support
─────────────────────────────────────────────────────────────
Legitimate (0)     0.9949      0.9983    0.9966        585
Fraud      (1)     0.9987      0.9961    0.9974        763
─────────────────────────────────────────────────────────────
Accuracy                                 0.9970      1,348
Macro Average      0.9968      0.9972    0.9970      1,348
Weighted Average   0.9970      0.9970    0.9970      1,348
```

### 7.3 Confusion Matrix

```
                          Predicted
                    Legitimate    Fraud
              ┌──────────────┬──────────────┐
Actual  Legit │  TN = 584    │  FP = 1      │   585
              ├──────────────┼──────────────┤
        Fraud │  FN = 3      │  TP = 760    │   763
              └──────────────┴──────────────┘
                    587           761          1,348
```

| Cell | Count | Interpretation |
|------|-------|----------------|
| True Negatives (TN) | 584 | Legitimate messages correctly classified as legitimate |
| True Positives (TP) | 760 | Fraud messages correctly classified as fraud |
| False Positives (FP) | 1 | Legitimate message incorrectly classified as fraud |
| False Negatives (FN) | 3 | Fraud messages incorrectly classified as legitimate |
| **Total Errors** | **4** | **Out of 1,348 test samples** |

### 7.4 Metric Computation

$$\text{Accuracy} = \frac{TP + TN}{TP + TN + FP + FN} = \frac{760 + 584}{1348} = 99.70\%$$

$$\text{Precision} = \frac{TP}{TP + FP} = \frac{760}{761} = 99.87\%$$

$$\text{Recall} = \frac{TP}{TP + FN} = \frac{760}{763} = 99.61\%$$

$$\text{F1\text{-}Score} = 2 \times \frac{\text{Precision} \times \text{Recall}}{\text{Precision} + \text{Recall}} = 2 \times \frac{0.9987 \times 0.9961}{0.9987 + 0.9961} = 99.74\%$$

### 7.5 Validation of High Accuracy

The 99.70% accuracy warrants scrutiny. The following checks were performed to rule out methodological errors:

| Validation Check | Method | Result |
|-----------------|--------|--------|
| **Data leakage** | Computed intersection of train and test text sets | 0 overlapping messages |
| **Stratification** | Compared class ratios in train vs test splits | Identical (56.6% fraud in both) |
| **TFLite parity** | Ran all 1,348 test samples through TFLite interpreter | 99.70% (matches original model exactly) |
| **Random baseline** | Majority-class classifier accuracy | 56.6% (fraud-always) — model significantly exceeds this |
| **Overfitting check** | Train accuracy (99.4%) vs Test accuracy (99.7%) | No overfitting gap — test accuracy equals or exceeds training |

**Conclusion:** The high accuracy is attributed to strong signal separation in the dataset. Fraud messages contain distinctive linguistic patterns (urgency language, payment demands, malicious URLs, impersonation cues) that are largely absent from legitimate messages. A 24.5M-parameter transformer model with pre-trained language understanding is well-suited to capture these patterns with high fidelity.

---

## 8. Error Analysis

### 8.1 Summary

Of 1,348 test samples, 4 were misclassified:
- **3 False Negatives** — fraud messages missed by the model
- **1 False Positive** — legitimate message incorrectly flagged

### 8.2 False Negatives (Missed Fraud)

| # | Message (Truncated) | True Label | Predicted | Confidence | Root Cause |
|---|---------------------|-----------|-----------|------------|------------|
| 1 | "Notice: Water connection under review. Verify & pay Rs. 7935: http :// waterbill . support/track/7Ybwc..." | Fraud | Legitimate | 0.0000 | URL obfuscation: spaces within URL (`http :// waterbill . support`) prevent tokenizer from recognizing it as a URL pattern |
| 2 | "Hi, this is City Power. Your account has Rs.21692 dues. Complete payment at https://tinyurl.com/TOmWwh..." | Fraud | Legitimate | 0.0000 | URL shortener: `tinyurl.com` is a legitimate domain, masking the phishing destination |
| 3 | "UPI refund pending. Claim now at http :// upi-refund . support/portal/GkPbq..." | Fraud | Legitimate | 0.0000 | URL obfuscation: same pattern as #1, spaces break URL recognition |

### 8.3 False Positives (False Alarms)

| # | Message | True Label | Predicted | Confidence | Root Cause |
|---|---------|-----------|-----------|------------|------------|
| 1 | "Bank notice: Please ignore suspicious calls/SMS asking for OTP." | Legitimate | Fraud | 1.0000 | Keyword overlap: contains terms strongly associated with fraud ("Bank notice", "suspicious", "OTP") despite being a legitimate security advisory |

### 8.4 Error Pattern Analysis

| Error Pattern | Occurrences | Impact | Mitigation in Production |
|---------------|-------------|--------|--------------------------|
| **URL obfuscation** (spaces in URLs) | 3 of 4 errors | Fraud messages with manipulated URLs evade tokenizer | Handled by Tier 2 (Domain Intelligence Module) which performs URL extraction before NLP analysis |
| **Keyword ambiguity** (fraud terms in legitimate warnings) | 1 of 4 errors | Legitimate bank security warnings use fraud-associated vocabulary | Multi-tier pipeline: Rule Engine (Tier 3) and Structural Features provide counterbalancing signals |

---

## 9. Model Export and Quantization

### 9.1 TFLite Conversion

The trained TensorFlow model is converted to TFLite format using a custom wrapper that simplifies the input interface:

**Original Model Interface:**
- Inputs: `input_ids`, `attention_mask`, `token_type_ids` (3 tensors)
- Output: `logits` [1, 2] (raw, unnormalized)

**TFLite Wrapper Interface:**
- Input: `input_ids` [1, 128] (int32) — single tensor
- Output: `fraud_probability` [1, 1] (float32) — single value

The wrapper internally generates `attention_mask` (non-zero positions → 1) and `token_type_ids` (all zeros) from `input_ids`, then applies softmax to extract the fraud class probability.

### 9.2 Quantization Details

| Property | Value |
|----------|-------|
| Quantization method | Dynamic Range Quantization |
| Original model size (TF SavedModel) | ~100 MB |
| Quantized TFLite model size | **25.5 MB (26,728,656 bytes)** |
| Compression ratio | ~4× |
| Accuracy after quantization | 99.70% (no degradation) |
| Supported operator sets | TFLITE_BUILTINS + SELECT_TF_OPS |
| Estimated arithmetic operations | 5.311 billion MACs |

Dynamic range quantization was chosen over full integer (int8) quantization because:
- It provides significant size reduction (4×) with zero accuracy loss
- It does not require a representative calibration dataset
- It maintains float32 precision during inference for attention computations

### 9.3 TFLite Verification

All 1,348 test samples were run through the exported TFLite model via the TensorFlow Lite Interpreter to verify numerical equivalence:

| Checkpoint | Cumulative Accuracy |
|------------|-------------------|
| 300 / 1,348 | 100.0% |
| 600 / 1,348 | 99.5% |
| 900 / 1,348 | 99.7% |
| 1,200 / 1,348 | 99.7% |
| **1,348 / 1,348** | **99.70%** |

The TFLite model produces identical classification decisions to the original TensorFlow model on all 1,348 test samples.

---

## 10. Deployment and On-Device Integration

### 10.1 Deployment Artifacts

| File | Location | Size | Purpose |
|------|----------|------|---------|
| `fraud_model.tflite` | `assets/models/` | 25.5 MB | Quantized MobileBERT model for inference |
| `vocabulary.json` | `assets/nlp/` | 519.5 KB | WordPiece vocabulary (30,522 token-to-index mapping) |
| `nlp_config.json` | `assets/nlp/` | 0.5 KB | Model configuration, thresholds, special token IDs, training metadata |
| `model_weights.json` | `assets/nlp/` | 0.2 KB | Model metadata (parameter count, quantization type) |

### 10.2 On-Device Inference Pipeline

The model is integrated into the SMISDroid Flutter application via the `tflite_flutter` package (v0.12.1) in `lib/nlp/nlp_classifier.dart`:

```
Incoming SMS Text
       │
       ▼
NlpClassifier.classify(text)
       │
       ├── 1. Preprocess: lowercase, strip non-alphanumeric characters
       │
       ├── 2. Tokenize: map words to vocabulary indices
       │
       ├── 3. Pad/Truncate to 128 tokens
       │
       ├── 4. Run TFLite Interpreter (4 threads)
       │
       └── 5. Output: fraud probability (float, 0.0 – 1.0)
              │
              ▼
       Risk Scoring Engine
       (NLP score weighted at 40% in final risk formula)
```

### 10.3 Role in Multi-Tier Pipeline

The NLP model serves as **Tier 1** in the SMISDroid three-tier detection pipeline:

| Tier | Component | Weight | Function |
|------|-----------|--------|----------|
| **Tier 1 (This Model)** | **NLP Classifier** | **40%** | **Semantic intent analysis of message text** |
| Tier 2 | Domain Intelligence Module | 30% | URL/domain infrastructure analysis |
| Tier 3 | Heuristic Rule Engine | 20% | Keyword pattern and combination matching |
| Tier 4 | Structural Features | 10% | Message formatting anomaly detection |

**Final Risk Score** = 0.40 × NLP + 0.30 × Domain + 0.20 × Rules + 0.10 × Structural

### 10.4 Fallback Mechanism

If the TFLite model fails to load (missing file, insufficient memory, unsupported device), the NLP classifier automatically falls back to a keyword-weighted scoring system with 27 fraud indicator terms. This ensures SMS analysis remains operational under all conditions.

---

## 11. Reproducibility

### 11.1 Random Seeds

All stochastic operations use a fixed seed of 42:

```python
random.seed(42)
numpy.random.seed(42)
tensorflow.random.set_seed(42)
```

### 11.2 Software Versions

| Package | Version |
|---------|---------|
| Python | 3.10 |
| TensorFlow | 2.21.0 |
| Transformers (Hugging Face) | 4.x (< 5.0) |
| scikit-learn | 1.7.2 |
| pandas | 2.3.3 |
| NumPy | 2.2.6 |

### 11.3 Reproduction Steps

```bash
# 1. Create virtual environment
python3 -m venv model_training/venv
source model_training/venv/bin/activate

# 2. Install dependencies
pip install tensorflow "transformers<5" pandas scikit-learn tf-keras

# 3. Place train.csv in model_training/datasets/

# 4. Run training script (or execute Jupyter notebook cells)
cd model_training
python train_mobilebert.py

# 5. Output files appear in model_training/output/ and assets/
```

---

## 12. Limitations

### 12.1 Known Limitations

| Limitation | Description | Severity | Mitigation |
|-----------|-------------|----------|------------|
| URL obfuscation | Spaces in URLs (`http :// domain . com`) bypass tokenizer | Medium | Tier 2 Domain Intelligence handles URL parsing independently |
| Keyword ambiguity | Legitimate security warnings contain fraud keywords | Low | Multi-tier scoring dampens single-tier false positives |
| English only | No support for Hindi, Hinglish, or regional Indian languages | High | Future: multilingual fine-tuning |
| Dataset scope | Trained on Indian financial SMS patterns specifically | Medium | May underperform on non-Indian fraud patterns |
| Model size | 25.5 MB vs initial target of <1 MB | Low | Acceptable for modern devices; int8 quantization could reduce to ~6 MB |
| Single-sentence input | Cannot process multi-message conversations | Low | SMS messages are inherently single-sentence |

### 12.2 Threats to Validity

| Threat | Assessment |
|--------|------------|
| **Selection bias** | Dataset may over-represent certain fraud templates. Real-world fraud is more diverse. |
| **Temporal drift** | Fraud patterns evolve. Model trained on 2024–2026 data may degrade over time. |
| **Adversarial evasion** | Attackers may craft messages specifically designed to evade MobileBERT classification. |
| **Distribution shift** | Production SMS distribution may differ from training data distribution. |

---

## 13. Conclusion and Future Work

### 13.1 Conclusion

This report documents the successful training and deployment of a MobileBERT-based SMS fraud detection model. Fine-tuned on 5,391 Indian financial SMS messages across six categories, the model achieves 99.70% accuracy, 99.87% precision, 99.61% recall, and a 99.74% F1-score on a held-out test set of 1,348 messages. The model was exported as a 25.5 MB quantized TFLite file with zero accuracy degradation and is deployed as Tier 1 of the SMISDroid multi-tier detection pipeline.

### 13.2 Future Work

| Priority | Enhancement | Expected Impact |
|----------|------------|-----------------|
| High | Multilingual fine-tuning (Hindi, Hinglish) | Expand coverage to non-English Indian SMS |
| High | Int8 full-integer quantization | Reduce model size from 25.5 MB to ~6 MB |
| Medium | URL-aware preprocessing | Detect obfuscated URLs before tokenization |
| Medium | Adversarial training with evasion samples | Improve robustness against crafted messages |
| Medium | Periodic retraining pipeline | Counter temporal drift in fraud patterns |
| Low | Multi-class classification (6 categories) | Provide fraud-type-specific alerts to users |
| Low | Confidence calibration | Improve probability estimates for risk scoring |

---

## 14. References

[1] Sun, Z., Yu, H., Song, X., Liu, R., Yang, Y., & Zhou, D. (2020). MobileBERT: a Compact Task-Agnostic BERT for Resource-Limited Devices. In *Proceedings of the 58th Annual Meeting of the Association for Computational Linguistics* (pp. 2158–2170). ACL.

[2] Devlin, J., Chang, M.W., Lee, K., & Toutanova, K. (2019). BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding. In *Proceedings of NAACL-HLT 2019* (pp. 4171–4186).

[3] Wu, Y., Schuster, M., Chen, Z., Le, Q.V., et al. (2016). Google's Neural Machine Translation System: Bridging the Gap between Human and Machine Translation. *arXiv preprint arXiv:1609.08144*.

[4] Kingma, D.P. & Ba, J. (2015). Adam: A Method for Stochastic Optimization. In *Proceedings of ICLR 2015*.

[5] TensorFlow Team. (2025). TensorFlow Lite Model Optimization. https://www.tensorflow.org/lite/performance/model_optimization

[6] Hugging Face. (2025). MobileBERT Model Card. https://huggingface.co/google/mobilebert-uncased

---

## 15. Appendix

### Appendix A: nlp_config.json

```json
{
  "model_type": "mobilebert",
  "model_name": "google/mobilebert-uncased",
  "max_seq_length": 128,
  "vocab_size": 30522,
  "input_type": "token_ids",
  "output_type": "fraud_probability",
  "threshold_safe": 0.3,
  "threshold_suspicious": 0.6,
  "pad_token_id": 0,
  "cls_token_id": 101,
  "sep_token_id": 102,
  "unk_token_id": 100,
  "version": "1.0.0",
  "training": {
    "epochs": 3,
    "batch_size": 16,
    "learning_rate": 2e-05,
    "train_samples": 5391,
    "test_samples": 1348,
    "test_accuracy": 0.997
  }
}
```

### Appendix B: model_weights.json

```json
{
  "type": "mobilebert",
  "base_model": "google/mobilebert-uncased",
  "total_params": 24582914,
  "quantization": "dynamic_range",
  "tflite_size_bytes": 26728656
}
```

### Appendix C: File Manifest

| File | Path | Size | SHA-256 (first 8 chars) |
|------|------|------|------------------------|
| `fraud_model.tflite` | `assets/models/` | 25.5 MB | — |
| `vocabulary.json` | `assets/nlp/` | 519.5 KB | — |
| `nlp_config.json` | `assets/nlp/` | 0.5 KB | — |
| `model_weights.json` | `assets/nlp/` | 0.2 KB | — |

---

**End of Document**

**Document Version:** 1.0
**Classification:** Internal — Technical
**Prepared By:** SMISDroid Development Team
**Reviewed By:** —
**Approved By:** —
**Date:** March 21, 2026
