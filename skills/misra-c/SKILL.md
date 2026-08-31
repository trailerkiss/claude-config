---
name: misra-c
description: Write and check C against MISRA C:2012 (the coding standard for critical-systems C). Use this skill whenever the user asks to make C code MISRA-compliant, check or audit code against MISRA, run cppcheck's MISRA addon, interpret MISRA findings, write a deviation record, or write new C that should conform to the standard — and proactively when authoring embedded or safety-relevant C. The mechanical checking is a static-analyser's job (cppcheck's free MISRA addon); this skill drives that tool, interprets its output against the published MISRA C:2012 Example-Suite, and teaches how to write conforming C and record justified deviations. It references guidelines by number and paraphrases intent — it does NOT reproduce the copyrighted normative rule text.
---

# MISRA C:2012

MISRA C:2012 is a set of guidelines for using C in critical systems — originally automotive, now widely used in aerospace, medical, rail, industrial, and any codebase where a C defect is expensive. It exists because C has a large space of *undefined*, *unspecified*, and *implementation-defined* behaviour, and MISRA restricts the language to a safer subset and mandates practices that keep behaviour predictable.

Two things frame everything below. First, **conformance checking is a tool's job, not an eyeball's** — an analyser decides rule violations deterministically where the rule is decidable; a human reviews the rest. This skill's primary action is to run and interpret a checker, then advise. Second, **the normative rule text is copyrighted** (purchasable from misra.org.uk). This skill uses guideline *numbers*, short titles, paraphrased intent, and the freely-published Example-Suite — never large verbatim quotes of the standard.

## The shape of the standard

A MISRA C:2012 **guideline** is either a **Directive** (prefixed `Dir`, e.g. `Dir 4.12`) or a **Rule** (prefixed `Rule`, e.g. `Rule 21.3`). The difference matters for checking:

- **Rules** are expressed entirely in terms of what the source says, so a static analyser can check them (some fully, some approximately).
- **Directives** need information beyond the source — design intent, documentation, process — so a tool can only assist; a human closes them.

Every guideline has a **category** that governs whether you may deviate from it:

| Category | Meaning |
|---|---|
| **Mandatory** | Must be met. **No deviation permitted, ever.** |
| **Required** | Must be met, or covered by a **formal, documented deviation** with rationale. |
| **Advisory** | Recommended. May be disregarded, ideally still recorded, but no formal deviation needed. |

And each rule is **Decidable** or **Undecidable**. A decidable rule can always be answered yes/no from the code; an undecidable one (e.g. anything depending on all possible runtime values or the whole program) can only be approximated — tools err on the side of caution and may report false positives, or miss cases, so undecidable rules always warrant review.

The standard has grown: the base document (2012), **Amendment 1** (additional security rules), **Amendment 2 / 3** (C11/C18 support), and Technical Corrigenda. When you cite a rule, cite the number; when coverage matters, note which amendment set your tool implements.

## Checking with cppcheck (the free engine)

[cppcheck](https://cppcheck.sourceforge.io/) ships a MISRA addon that checks a large **decidable** subset of MISRA C:2012. It is the default engine for this skill because it is free, open-source, and scriptable. It does **not** cover every rule (undecidable rules and directives need review, and commercial tools such as Helix QAC, Polyspace, PC-lint Plus, Parasoft, Coverity, and ECLAIR cover more) — so "cppcheck clean" means "clean against the rules cppcheck implements," which the report must state honestly.

### Install

```bash
# Debian/Ubuntu
sudo apt-get install -y cppcheck        # the misra addon ships inside the package
cppcheck --version
python3 --version                       # the addon is a python script
```

If `apt` needs root you don't have, cppcheck also has portable/conda builds; the addon is `addons/misra.py` inside the install.

### Run

Check one translation unit, or a project, scoped to **your own source only** — never third-party or vendored libraries, which are out of scope for your compliance argument:

```bash
cppcheck --addon=misra \
         --enable=style,warning \
         --std=c99 \
         --platform=unix64 \
         -I include \
         --suppress=missingIncludeSystem \
         path/to/your/src 2> misra-findings.txt
```

Findings look like:

```
src/protection.c:41:5: style: [misra-c2012-21.3] ...
```

The bracketed `misra-c2012-<n>.<m>` is the guideline. Without a rule-texts file you get the number only, which is enough to look the rule up.

### Full rule text (only if you own the standard)

If you have the licensed MISRA C:2012 PDF, you may put its rule texts into a local file and pass it, so findings print the wording:

```bash
# misra.json
{ "script": "misra", "args": [ "--rule-texts=misra_rules.txt" ] }
```

```bash
cppcheck --addon=misra.json ...
```

The `misra_rules.txt` format is one block per rule — `Rule 21.3` on its own line, then its text — built by hand from your licensed copy. **Do not commit that file to a public repo**; it contains MISRA's copyrighted text. Without it, number-only output is perfectly usable.

### Baseline and CI

To make conformance *continuous* rather than a one-off, add a cppcheck-misra step to CI (e.g. GitHub Actions) so every push is checked:

```yaml
- run: sudo apt-get install -y cppcheck
- run: cppcheck --addon=misra --enable=style,warning --std=c99 <your-src> 2> misra.txt; cat misra.txt
```

Decide whether it **gates** (fails the build on any finding) or **reports** (annotates only). For an evolving codebase, start non-gating with a suppression baseline, then tighten.

## The Example-Suite as your reference

MISRA publishes an **Example-Suite** (`gitlab.com/MISRA/MISRA-C/MISRA-C-2012/Example-Suite`) of small annotated files, one topic per guideline, showing compliant and non-compliant code. It is the authoritative illustration of what each rule means without needing the prose. Clone it once and consult it whenever a finding is unclear:

```bash
git clone https://gitlab.com/MISRA/MISRA-C/MISRA-C-2012/Example-Suite.git
```

Check the repository's own `LICENSE` before reusing files — it is published by MISRA for validation use, and the licence in the repo governs what you may copy. File names encode the guideline: `R_21_03.c` is Rule 21.3, `D_04_12.c` is Directive 4.12. Inside, lines are marked with comments such as `/* Compliant */` and `/* Non-compliant */`. When you explain a finding, cite the matching suite file so the user can see the canonical example — but paraphrase; don't paste large excerpts if the licence doesn't allow it.

## Writing MISRA-clean C from the start

The cheapest MISRA fix is not writing the violation. These are the guidelines that most often bite ordinary C — paraphrased intent plus the number, with the shape of compliant code. Consult the Example-Suite file (`R_xx_yy.c`) for the canonical case.

**Library and environment restrictions (the ones that flood application code):**

- `Dir 4.12` / `Rule 21.3` — **no dynamic memory** (`malloc`/`calloc`/`realloc`/`free`). Critical systems favour static or stack allocation with known bounds. Compliant: fixed-size buffers sized at compile time, or a pre-allocated pool.
- `Rule 21.6` — **no `<stdio.h>` standard I/O** (`printf`, `fopen`, …). Use a project logging abstraction, not `printf`, in conforming code.
- `Rule 21.5` — **no `<signal.h>`**; `Rule 21.8/21.9/21.10` — restrictions on `<stdlib.h>` (`system`, `abort`, `exit`, `getenv`, `qsort`, `bsearch`) and `<time.h>`.
- These are why OS-level application code (threads, sockets, signals, heap) diverges from MISRA — such code typically carries **deviations**, not fixes.

**The essential type model (`Rule 10.x`)** — the subtlest and most common source of real findings. C's implicit conversions are a defect source, so MISRA defines "essential types" (essentially-signed, -unsigned, -Boolean, -character, -floating) and forbids mixing or narrowing them implicitly:

```c
/* Non-compliant: implicit float -> narrower signed, and mixed signedness */
int32_t x = ipk * sinf(a) * 1000.0f;      /* 10.x: assignment narrows essential float to signed */

/* Compliant: make the conversion explicit and intended */
int32_t x = (int32_t)(ipk * sinf(a) * 1000.0f);
```

Related: `Rule 10.1` (operands of the right essential type), `10.3` (no assignment to a narrower or different-category type), `10.4` (both operands of an arithmetic operator the same essential type).

**Control flow and functions:**

- `Rule 15.5` (advisory) — a function should have a **single point of exit** at the end. Early `return`s are flagged; refactor to a single `return` if you want the advisory clean.
- `Rule 15.6` (required) — the body of `if`/`else`/`for`/`while` **must be a compound `{ }`**, even for one statement.
- `Rule 17.2` (required) — **no recursion**, direct or indirect.
- `Rule 17.7` — the value returned by a non-void function **must be used** (or explicitly cast to `(void)`).
- `Rule 8.7` (advisory) — objects/functions used in only one file should have **internal linkage** (`static`).
- `Rule 8.2` — function types must be in prototype form with named parameters.

**Pointers, preprocessor, expressions:**

- `Rule 11.x` — restrict pointer conversions (no casting away `const`, careful integer↔pointer).
- `Rule 20.x` / `Rule 21.1` — restrict the preprocessor (no redefining reserved identifiers; parenthesise macro parameters — `#define SQ(x) ((x) * (x))`).
- `Rule 13.x` — no assignment/side-effects in surprising places; beware sequence-point issues.
- `Dir 4.6` — use the fixed-width typedefs (`int32_t`, `uint16_t`) rather than bare `int`/`short` where size matters.
- `Rule 2.x` — no dead code, unused variables, or unreachable code.

Write with these in mind and most of the mechanical findings never appear; what remains is the genuinely interesting set that needs a decision.

## Deviations and scope

Not every finding is a defect. MISRA's own **compliance framework** (the separate *MISRA Compliance:2020* document) expects that some Required/Advisory guidelines are consciously **deviated** from, with a record. A deviation names the guideline, the code it covers, and — crucially — the **rationale** and any mitigation. **Mandatory guidelines can never be deviated.** When a finding is inherent to the domain (e.g. `Rule 21.6` in code that must log via `printf` for a demo, or `Rule 21.3` where a third-party API allocates), the correct output is a deviation record, not a contortion of the code:

```
Deviation: Rule 21.3 (Required) — use of calloc in RmsWin_init()
  Scope:     relay/protection.c, RmsWin_init
  Rationale: the RMS window is sized from a runtime sample rate; a demo, not
             a freestanding target. Allocation is once at init, checked, freed
             in RmsWin_free. Mitigation: no per-cycle allocation.
```

Two scope rules keep the exercise honest: apply MISRA to **your own source only**, not vendored libraries (you don't own their conformance); and state the **checking tool and its coverage** in any compliance claim ("checked with cppcheck MISRA addon — decidable subset; undecidable rules and directives reviewed manually").

## Producing a compliance report

When asked to "check" code, produce a report, not a raw dump:

1. Run cppcheck-misra scoped to the user's source; capture findings.
2. **Group by guideline number**, most-frequent first, with a count.
3. For each group: the rule number + paraphrased intent, an example location, and a verdict — **fix** (a real defect), **deviate** (justified, draft the record), or **false positive** (undecidable-rule noise; note why).
4. Separate **Mandatory** findings (must fix — cannot deviate) at the top.
5. State coverage honestly: which rules the tool checks, and that directives/undecidable rules need manual review.
6. Offer to apply the fixes and write the deviation records.

## Common mistakes

- **Treating every finding as a defect.** Many are deviations-by-design for the domain. Sort fix vs deviate vs false-positive; don't mangle correct code to silence an advisory.
- **Checking third-party code.** Scope to your own source. libiec61850, POSIX headers, generated code — out of scope.
- **Claiming "MISRA compliant" from one tool.** No single free tool covers all rules. Say "checked against the decidable subset cppcheck implements."
- **Deviating a Mandatory rule.** Not allowed — those must be fixed.
- **Pasting the normative rule text.** It's copyrighted. Cite numbers, paraphrase, and point at the Example-Suite.
- **Silencing with blanket suppressions.** A suppression without a rationale is an undocumented deviation. Record why.

## Checklist before calling code "checked"

- cppcheck-misra run, scoped to the project's own source, output captured
- Findings grouped by guideline, Mandatory ones surfaced first
- Each finding classified: fix / deviate (with rationale) / false-positive (with reason)
- Deviation records drafted for the justified ones; none for Mandatory rules
- Coverage stated: tool used, decidable subset, directives/undecidable reviewed manually
- The report says what was checked and what a human still needs to close
