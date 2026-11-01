# Run helper tests and selected BG chunks only; no native tract notebook execution.
# Rscript tests/test_rental_inventory_bg.R
bg_only <- TRUE
source(here::here("tests", "test_rental_inventory.R"))
