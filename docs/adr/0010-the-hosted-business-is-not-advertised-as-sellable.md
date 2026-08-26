# ADR 0010 — The hosted business is not advertised as sellable

- Status: accepted (2026-08-26)
- Context: ADR 0005 decided that anyone may run Kern as a paid service — the AGPL permits it and the
  billing module ships in the public image for exactly that — and that the name, not the licence, is
  what we hold back, monetised through a Kern Certified Host programme with a revenue share. The
  marketing site, `TRADEMARK.md`, `LICENSING.md` and the billing docs then advertised that permission
  in plain words: "You sell hosted Kern to other people. Allowed, and we mean it." A pre-1.0 product
  read by potential customers, investors and competitors does not benefit from a page teaching every
  reader that reselling our own hosting business is legal. The permission is the AGPL's, not ours to
  grant or to take back; whether we point at it is ours.

## Decision

1. **The licence position does not change.** Anyone may still run Kern as a paid service under the
   AGPL's terms: publish modifications served over a network, do not call it Kern. No document states
   or implies a restriction that the licences do not carry.
2. **We stop advertising it.** The website, `TRADEMARK.md`, `LICENSING.md` and the docs no longer say
   "you may sell hosted Kern" as an offered feature, and the Certified Host programme is not
   described anywhere a visitor can read. The pages speak about running Kern for your company,
   building modules, contributing and forking instead.
3. **Trademark answers are unchanged in substance.** What needs permission (calling a service Kern,
   implying endorsement) and what does not (honest reference, comparison, review) stays stated in
   `TRADEMARK.md`, because a name policy that never says what it governs protects nothing.
4. **Nothing is forbidden that was permitted.** This is a decision about what we publish, not about
   what others may do. If someone asks, the honest answer remains yes, within the licence and the
   trademark policy.

## Consequences

- A competitor who wants reassurance that reselling is lawful reads the AGPL, which says it anyway;
  we have simply stopped doing the advertising for them.
- The Certified Host programme becomes something we offer in conversation rather than publish. Its
  terms were never written down outside this decision chain, so nothing public needs retracting.
- ADR 0005 remains the record of why the licence permits resale; this ADR records why our surfaces no
  longer market it. They are read together.
- If a third party operates a hosted Kern service at scale, the trigger written in ADR 0005 (moving
  future releases to a source-available licence) still stands, unchanged by this decision.
