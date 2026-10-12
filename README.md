# MedPrep shared MCQ platform starter

This starter is designed for a shared student website: email/password accounts, a Supabase database, student-specific bookmarks and attempts, and administrator-only question management.

## What you need
- A free Supabase account/project.
- A free static hosting account (Cloudflare Pages is a suitable option for a static HTML app).
- No Lovable account and no paid AI website builder.

## 1. Create the database
1. Create a project at https://supabase.com.
2. Open **SQL Editor** in the Supabase dashboard.
3. Run all of `SETUP.sql`.
4. Open **Authentication → URL Configuration** and set the Site URL to your eventual public website address. During testing you can use the hosting preview URL.
5. In **Authentication → Providers**, check that Email is enabled.

## 2. Configure the app
1. Open `index.html` in a text editor.
2. Near the bottom, find:
   `const SUPABASE_URL = "PASTE_YOUR_SUPABASE_PROJECT_URL";`
   `const SUPABASE_ANON_KEY = "PASTE_YOUR_SUPABASE_ANON_KEY";`
3. Replace these with the Project URL and publishable/anon key from **Supabase → Project Settings → API**.
4. The publishable/anon key is meant for browser use; do not paste a `service_role` secret into the website.

## 3. Make your account the administrator
1. Sign up through the site once it is configured.
2. In Supabase, open **Authentication → Users** and copy your account's UUID.
3. In SQL Editor, run this, replacing the placeholder:
   `update public.profiles set role = 'admin' where id = 'YOUR-USER-UUID';`
4. Sign out and sign in again. You should now see the question-management form.

Do not give the admin role to untrusted users.

## 4. Publish free
For a simple static site:
1. Create a GitHub repository and upload `index.html` (and optionally this README and `SETUP.sql`).
2. In Cloudflare, open Workers & Pages → Create → Pages → Connect to Git.
3. Select the repository. Leave the build command empty and set the output directory to `/` (or the repository root, depending on the dashboard UI).
4. Deploy. The site will have a `pages.dev` address.
5. Set that public URL in Supabase Authentication URL Configuration.

Official docs:
- Supabase quickstart: https://supabase.com/docs/guides/getting-started
- Supabase Auth: https://supabase.com/docs/guides/auth
- Cloudflare Pages: https://pages.cloudflare.com/

## Important security and content notes
- `questions_public` intentionally omits the correct answer. Answer checking is performed by the database function `submit_mcq_answer`.
- The app is a starter and should be thoroughly tested before public use. Confirm RLS policies, email confirmation redirects, and the admin-role flow in your project.
- Clinical questions in your own bank should be reviewed for accuracy and include appropriate references. Avoid copyrighted question text from commercial question banks.
- This app does not use AI to generate medical content. AI generation can be added later with a server-side API route; never put a private AI API key in browser JavaScript.
