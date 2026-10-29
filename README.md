# Lot Tag Desk

SKU and barcode tag generator for sorting supplier and customer lots.

The page is passcode-locked: `index.html` contains only encrypted data (AES-256-GCM, key derived from the passcode with PBKDF2-SHA256, 600,000 rounds). Ask the owner for the passcode.

Saved lots are stored in the browser of the device that saved them.
