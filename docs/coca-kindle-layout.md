# COCA-English Kindle layout notes

The supplied COCA-English note type was designed for modern browser engines. Its original stylesheet relies heavily on CSS custom properties (`var(--...)`), flexbox `gap`, responsive media queries, and 48–52px headline sizing. Its templates also include modern JavaScript (`let`, `const`, arrow functions, template literals, `URLSearchParams`, `NodeList.forEach`) that Kindle's old WebKit does not parse reliably.

Kanki therefore applies a Kindle-only, plain-CSS override when these COCA classes are present. The desktop/mobile Anki styling remains untouched.

Target presentation:
- Word: ~34px, bold, compact header.
- Part of speech: 16px inline badge.
- IPA: 20px.
- Definition: 21px / 1.45.
- Examples: 20px / 1.42, with target word bold + underlined for e-ink contrast.
- Audio button: 28px.
- No dictionary logo, card shadow, or decorative background on Kindle.
- Reduced separators and margins to minimize vertical scrolling.

The override uses only old-WebKit-safe CSS values and avoids CSS variables for the Kindle path.
