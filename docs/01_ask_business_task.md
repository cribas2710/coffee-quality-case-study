# Phase 1 — Ask: Business Task Definition

**Project:** What Makes Great Coffee? Quality Drivers for a Honduran Coffee Cooperative
**Author:** Marzell Cribas
**Role:** Junior Data Analyst, Business Intelligence Consulting (Google Data Analytics Capstone)
**Tools:** SQL (BigQuery) · Python (pandas, matplotlib/seaborn, SciPy) · Tableau Public

> *Scenario note: the client is a fictional organization created for this capstone. The data is real and public.*

---

## 1. Client Background

**Cooperativa Cafetalera Hondureña (fictional)** is a mid-sized coffee cooperative in Honduras. It groups smallholder farmers and sells green Arabica coffee to export buyers.

Most of its coffee sells at commodity prices. Leadership wants to move more of its volume into the **specialty coffee market**, where coffee scoring **80+ points** on the SCA cupping scale earns a significant price premium.

To decide where to invest (farm selection, post-harvest processing, quality control), they have hired our consultancy to analyze what drives coffee quality worldwide, and where Honduras stands.

## 2. Business Task

> **Identify which origin and processing factors are associated with higher cupping scores and fewer defects in Arabica coffee, and use these insights to recommend where the cooperative should invest to increase the share of its coffee that qualifies as specialty grade (80+ points).**

## 3. Stakeholders

| Stakeholder | Role | What they need |
|---|---|---|
| **General Manager** (primary) | Final decision-maker on investments | Clear, prioritized recommendations with expected impact |
| **Board of Directors** (primary) | Approves budget | High-level benchmark: how Honduras compares to competitors |
| **Agronomists & mill supervisors** (secondary) | Execute changes on farms and at the wet mill | Specific, actionable practices (altitude, processing, defect control) |
| **Consulting manager** (internal) | Reviews analysis quality | Sound methodology, documented limitations |

## 4. Guiding Questions

1. **Benchmark:** How does Honduras rank in average cupping score versus other major producers (Colombia, Guatemala, Costa Rica, Ethiopia, Brazil)?
2. **Altitude:** Is altitude associated with higher scores? Is there an altitude range linked to the best quality?
3. **Processing:** Which processing method is associated with higher scores and fewer defects?
4. **Defects:** How strongly are Category 1 and Category 2 defects associated with lower total scores?
5. **Sensory profile:** In which sensory attributes (aroma, flavor, acidity, body, balance, etc.) does Honduran coffee outperform or underperform competitors?

## 5. Key Metrics & Definitions

| Metric | Definition |
|---|---|
| **Total Cup Points** | Overall cupping score (0–100) from certified Q-graders. Sum of 10 sensory attributes |
| **Specialty grade** | Total Cup Points ≥ 80 (SCA standard) |
| **Specialty rate** | % of samples scoring ≥ 80 within a group |
| **Category 1 defects** | Primary (severe) defects in the green sample, e.g., full black or sour beans, foreign matter |
| **Category 2 defects** | Secondary defects, e.g., partial black or sour, broken, insect-damaged or immature beans |
| **Altitude (mean, m)** | Mean farm altitude in meters above sea level (standardized during cleaning) |

## 6. Scope

**In scope**
- Arabica samples from the Coffee Quality Institute (CQI) database
- Country-level benchmarking, altitude, processing method, defects, and sensory attributes
- Descriptive and correlational analysis

**Out of scope**
- Robusta coffee (different grading scale)
- Price and market data
- Causal claims: the data is observational, so findings describe associations, not causes

## 7. Deliverables

1. Clean, documented dataset with a cleaning changelog
2. SQL queries and a Python notebook covering the full analysis
3. Interactive Tableau Public dashboard
4. Executive presentation for the General Manager and Board
5. Top 3 data-driven recommendations and next steps

## 8. Success Criteria

The project is successful if the cooperative's leadership can answer:
- *"Where do we stand against our competitors?"*
- *"Which 2–3 investments are most likely to raise our specialty rate?"*

…using evidence from the analysis, with its limitations clearly stated.
