# Bundled images

Downloaded once (not loaded from network at runtime — see the parent
task's own reasoning) from the AI-generated mockup set at
`web/stitch_fresh_farm_direct/` (Google Stitch design-tool output,
`lh3.googleusercontent.com/aida-public/...` URLs). These are AI-generated
placeholder/prototype photography, not licensed commercial stock or real
product photos — swap for real photography before shipping to production.

- `branding/logo.jpg` — combined Freshoza logo mark (from `shop_fresh`).
- `products/{product-id}.jpg` — one per seeded catalog product id (see
  `services/local-dev/_catalog_seed_data.py`), sourced from
  `product_categories`, `shop_fresh`, and `my_cart`.
