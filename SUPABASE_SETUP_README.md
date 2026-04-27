# Reconditioning tracker Supabase setup

Files in this ZIP:

- `reconditioning_tracker_supabase.html`: the website.
- `reconditioning_supabase_setup.sql`: SQL to run once in Supabase.
- `SUPABASE_SETUP_README.md`: this setup guide.

## Quick setup

1. Create a free Supabase project.
2. Open SQL Editor in Supabase.
3. Paste and run `reconditioning_supabase_setup.sql`.
4. Copy your Project URL.
5. Copy your publishable key. Legacy anon key also works.
6. Host `reconditioning_tracker_supabase.html` on an HTTPS static host, such as Netlify, Vercel or GitHub Pages.
7. Open the hosted page on the laptop.
8. Enter the Supabase URL, key, device name and a long private sync phrase.
9. Click `Connect and sync`.
10. Open the same hosted page on the phone.
11. Enter the same Supabase URL, same key and same private sync phrase.
12. Click `Connect and sync`.

The app saves locally first. If online and connected, it pulls the cloud copy, merges records, and pushes the merged data back to Supabase.

## Security notes

- Never put the service role key or secret key into this website.
- Use only the publishable key or legacy anon key.
- The SQL enables RLS on the data table and revokes direct table access from anon and authenticated roles.
- The table has no direct anon access.
- The website only uses RPC functions.
- The private sync phrase is not uploaded as plain text. The browser derives a sync ID and secret using SHA-256.
- Use a long unique phrase. Do not reuse an important password.

## Data stored

The cloud payload contains:

- programme start date
- weekly progress
- task checkboxes
- strength sessions, including sets, reps, load, RPE and notes

The cloud payload intentionally does not include the Supabase key, sync phrase, full name, address, NHS number, date of birth or diagnosis list.
