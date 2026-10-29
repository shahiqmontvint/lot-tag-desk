# Lot Tag Desk

SKU and barcode tag generator for sorting supplier and customer lots.

The page is passcode-locked: `index.html` contains only encrypted data (AES-256-GCM, key derived from the passcode with PBKDF2-SHA256, 600,000 rounds). Ask the owner for the passcode.

After the passcode, each person signs in with their Supabase account. Lots, code tables, print jobs and scans are saved to the Supabase database (`supabase-setup.sql` creates the tables and access rules).
