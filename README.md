# SMISDroid

## Real-Time SMS Fraud Detection System (Secure-SMS Edge Defense)

---

## 1. System Overview

SMISDroid is a **privacy-preserving mobile security application** designed to detect and mitigate SMS-based financial fraud (smishing) in real time.

The system follows a **hybrid detection approach** combining:

* **Natural Language Processing (NLP)** for message intent detection
* **Domain Intelligence Module (DIM)** for URL and infrastructure analysis

All processing is performed **locally on the device**, with optional enhancement when internet connectivity is available.

---

## 2. Design Principles

### 2.1 Zero-Cloud Processing
* No SMS data is sent to external servers
* All detection logic runs on-device

### 2.2 Hybrid Detection
* Combines **AI-based semantic analysis** and **cybersecurity heuristics**

### 2.3 Offline First
* Core detection works without internet
* Online data enhances accuracy but is not mandatory

### 2.4 Real-Time Protection
* Detection is triggered immediately after message reception

---

## 3. System Architecture

The system follows a **modular pipeline architecture** with parallel analysis layers.

### Architecture Flow Diagram

```
Incoming SMS
      |
      v
SMS Listener (Android API)
      |
      v
Message Preprocessing
(Text Cleaning + URL Extraction + Metadata)
      |
      v
+---------------------- PARALLEL ANALYSIS ----------------------+
|                                                                |
|   NLP Intent Analysis (Local - TensorFlow Lite)                |
|   - Detect urgency, payment intent, scam language              |
|                                                                |
|   Domain Intelligence Module (DIM)                             |
|   - Offline Mode:                                              |
|       - TLD checks                                             |
|       - URL heuristics                                         |
|       - Cached domain reputation                               |
|   - Online Mode (if internet available):                       |
|       - Domain age (WHOIS)                                     |
|       - DNS validation                                         |
|                                                                |
+---------------------------+------------------------------------+
                            |
                            v
                  Risk Scoring Engine
     (Combine NLP + DIM + Rule Signals)
                            |
                            v
                    Decision Engine
         (Safe / Suspicious / Fraudulent)
                            |
                            v
               Active Mitigation Module
        (Alert User + Disable Malicious Links)
                            |
                            v
                Local Storage (SQLite)
     (Logs, Cached Domains, Trusted Senders)
```

---

## 4. Component Description

### 4.1 SMS Listener
Captures incoming SMS messages using Android APIs.

**Input:**
* Raw SMS message

**Output:**
* Message body
* Sender ID
* Timestamp

### 4.2 Message Preprocessing
Prepares data for analysis.

**Functions:**
* Text normalization
* URL extraction using regex
* Metadata extraction

### 4.3 NLP Intent Analysis Module
**Technology:** TensorFlow Lite

Performs **on-device text classification**.

**Purpose:**
* Detect semantic fraud indicators such as:
  * Urgency
  * Payment request
  * Service disruption

**Output:**
* Fraud probability score

### 4.4 Domain Intelligence Module (DIM)
Analyzes URLs embedded in the message.

#### Offline Mode (Always Available)
* Suspicious TLD detection
* URL structure analysis
* Keyword presence in domain
* Cached domain lookup

#### Online Mode (Optional Enhancement)
* Domain age verification (WHOIS/RDAP)
* DNS record validation (via DNS-over-HTTPS)

**Output:**
* Domain risk score (0-100)

### 4.5 Heuristic Rule Engine
Applies predefined fraud detection rules.

**Examples:**
* "disconnect" + "payment" + link
* Suspicious sender patterns

**Output:**
* Rule-based risk score

### 4.6 Risk Scoring Engine
Aggregates outputs from all modules.

**Formula:**
```
RiskScore =
    (w1 x NLP Score)
  + (w2 x Domain Intelligence Score)
  + (w3 x Rule Score)

Where:
  w1 = 0.40 (NLP weight)
  w2 = 0.35 (Domain weight)
  w3 = 0.25 (Rule weight)
```

### 4.7 Decision Engine
Classifies messages based on risk score.

| Score Range | Classification |
|-------------|----------------|
| 0.0 - 0.3   | Safe           |
| 0.3 - 0.6   | Suspicious     |
| 0.6 - 1.0   | Fraudulent     |

### 4.8 Active Mitigation Module
Protects the user from interaction with malicious content.

**Actions:**
* Display warning notification
* Disable or mask suspicious links
* Highlight risky messages

### 4.9 Local Storage
**Technology:** SQLite

Stores:
* Cached domain results
* Trusted sender list
* Detection logs

---

## 5. Workflow Summary

```
SMS Received
-> Preprocessing
-> NLP Analysis (Local)
-> Domain Intelligence (Offline + Optional Online)
-> Rule Engine
-> Risk Scoring
-> Decision
-> Mitigation
```

---

## 6. System Behavior Scenarios

### Case 1: No Internet
```
NLP + Offline DIM + Rule Engine -> Decision
```

### Case 2: Internet Available
```
NLP + Offline DIM + Online DIM + Rule Engine -> Enhanced Decision
```

### Case 3: No URL in Message
```
NLP + Rule Engine -> Decision
```

---

## 7. Key Advantages

* Fully **on-device processing**
* Works **offline and online**
* Combines **AI + cybersecurity techniques**
* Detects **zero-day phishing domains**
* Provides **active user protection**
* **Privacy-first** - no data leaves the device

---

## 8. Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/
│   ├── constants/
│   │   ├── app_colors.dart      # Color palette
│   │   ├── app_strings.dart     # UI strings
│   │   └── risk_thresholds.dart # Score thresholds
│   ├── theme/
│   │   └── app_theme.dart       # Material theme
│   └── utils/
│       ├── extensions.dart      # Dart extensions
│       └── logger.dart          # Logging utility
├── models/
│   ├── sms_analysis_result.dart # Analysis result model
│   ├── domain_score.dart        # Domain score model
│   └── nlp_result.dart          # NLP result model
├── services/
│   ├── sms_listener.dart        # SMS listener service
│   ├── risk_engine.dart         # Risk scoring engine
│   ├── rule_engine.dart         # Keyword rule engine
│   ├── preprocessor.dart        # Text preprocessing
│   ├── database_service.dart    # SQLite database
│   ├── notification_service.dart # Push notifications
│   └── domain_intelligence/
│       ├── domain_intelligence.dart # DIM orchestrator
│       ├── url_resolver.dart    # Redirect chain resolver
│       ├── dns_analyzer.dart    # DNS-over-HTTPS queries
│       ├── domain_scorer.dart   # Domain risk scoring
│       └── whois_analyzer.dart  # WHOIS/RDAP lookups
├── nlp/
│   └── nlp_classifier.dart      # TFLite text classifier
└── ui/
    ├── dashboard_screen.dart    # Main dashboard
    ├── alert_screen.dart        # Alert details
    └── widgets/
        ├── risk_badge.dart      # Risk level badge
        └── stat_card.dart       # Statistics card
```

---

## 9. Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter |
| Language | Dart |
| ML Runtime | TensorFlow Lite |
| Database | SQLite (sqflite) |
| SMS Access | Telephony package |
| DNS Queries | Cloudflare DNS-over-HTTPS |
| WHOIS | RDAP.org API |
| Charts | fl_chart |
| Notifications | flutter_local_notifications |

---

## 10. Getting Started

### Prerequisites
* Flutter SDK >= 3.0.0
* Android device/emulator (API 21+)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/smisdroid.git

# Navigate to project
cd smisdroid

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Permissions Required
* `READ_SMS` - Read incoming messages
* `RECEIVE_SMS` - Listen for new SMS
* `INTERNET` - Domain intelligence queries
* `POST_NOTIFICATIONS` - Show fraud alerts

---

## 11. Screenshots

*Coming soon*

---

## 12. License

This project is licensed under the MIT License.

---

## 13. Acknowledgments

* TensorFlow Lite for on-device ML
* Cloudflare for privacy-respecting DNS
* RDAP.org for WHOIS lookups
