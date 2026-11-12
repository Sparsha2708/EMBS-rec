# EMBS-rec
# redstone_rx

**A Minecraft-themed registration site for a student healthcare hackathon.**
*Mine ideas. Craft cures. Respawn healthcare.*

One static HTML file, a Supabase backend, and no build step. Participants sign up, register a team of 1 to 4 through a guided wizard, and organizers review applications.

---

## What it does

- **Event landing page** with a pixel-art hero, mission, tracks, timeline, prizes, judging criteria and FAQ. All event content lives in one `EVENT` config object, so organizers update details without touching layout code.
- **Account system** with email and password sign-up and login, plus email confirmation via Supabase Auth.
- **Team registration wizard** covering team size, team lead, members, track and eligibility, abstract, and a review step. Each step is validated before the user can continue.
- **Edit your application** while its status is still `pending`. Once organizers approve or reject it, it locks.
- **Six hackathon tracks:** Disease Prediction, Drug Discovery, Medical Imaging, Patient Monitoring, Healthcare Access and Open Innovation.
- **Custom pixel-art rendering.** The logo, hearts and hospital illustration are drawn from small character grids into SVG, with no image files.

## Tech stack

| Layer | Choice |
|---|---|
| Frontend | Vanilla HTML, CSS and JavaScript in a single file |
| Auth and database | Supabase (Postgres + Auth) |
| Client library | `@supabase/supabase-js` v2, pinned, loaded from jsDelivr |
| Security | Postgres Row Level Security, constraints and a guard trigger |
| Hosting | Any static host (Netlify, Vercel, GitHub Pages, Cloudflare Pages) |

## Architecture

```
 Browser (index.html)
      │   supabase-js, using the public anon key
      ▼
 Supabase
   ├─ Auth            sign-up, login, sessions
   └─ Postgres
        ├─ registrations   one row per user, protected by RLS
        └─ admins          organizer allow-list
```

There is no custom server. Access control is enforced inside the database, where it can't be bypassed from the browser.

## Security model

The Supabase **anon key is public by design**, and it sits in the browser the same way in any frontend framework. Nothing is protected by hiding it. The data is protected by the database rules in `supabase_schema.sql`:

- **Row Level Security** is on for every table. A user can read and write only their own registration.
- **Guard trigger.** Users cannot set or change their own `status`, `user_id` or `email`. A participant can't approve themselves, even by calling the API directly.
- **Edit lock.** Updates are allowed only while `status = 'pending'`.
- **Database constraints** validate team size (1 to 4), team-name format, phone format, abstract length and the agreement checkbox. This is a second layer behind the browser checks.
- **Unique team names**, case-insensitive.
- **Organizer access** goes through the `admins` table and a `security definer` helper, so approving and rejecting is separate from participant access.
- The `service_role` key is never used or shipped.

I tested these rules against a real Postgres instance. The tests included a user trying to self-approve, spoof their identity, steal a taken team name, read another team's data and edit after approval. Each attempt was blocked.

## Why a single HTML file and not Vite?

**Short answer:** Vite would add tooling and wouldn't make the app any safer or better. For this project it was the wrong trade.

1. **It doesn't change the security story.** A common belief is that a bundler hides keys. It doesn't. Anything exposed to client code, including `VITE_*` environment variables, is bundled into the JavaScript that ships to every visitor. The anon key is visible in the browser with or without Vite. What keeps this app safe is Row Level Security, and that lives in Postgres.
2. **No build step means fewer things to break.** There's no `node_modules`, no lockfile churn, no dependency vulnerabilities to patch, and no CI pipeline. The page opens by double-clicking it and deploys by dragging one file onto a host.
3. **The app is small enough that a bundler has nothing to optimise.** One page, one script, one pinned library. Vite's main benefits are module bundling, tree-shaking and hot reload for large codebases. They don't apply here.
4. **Easy for non-developers to run.** Hackathon organizers can edit the `EVENT` object in a text editor and re-upload. No terminal required.
5. **Easy to audit.** A reviewer can read the entire client in one sitting, and there's no build output hiding what actually runs.

**When I'd switch to Vite or a framework:** multiple pages or routes, a component library, TypeScript, shared state across many views, or a team of several developers. At that point the structure is worth the tooling. For a single registration flow it isn't.

## Run it

1. **Create the database.** In your Supabase project, open the SQL Editor, paste all of `supabase_schema.sql` and run it. It's safe to re-run, and it repairs an older `registrations` table if one exists.
2. **Add your keys.** Near the top of the script in `index.html`, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` (Project Settings → API). Never use the `service_role` key here.
3. **Open it** in a browser, or deploy the file to any static host.
4. **Set the Site URL** in Supabase under Authentication → URL Configuration, so confirmation emails link back to your site.
5. **Make yourself an organizer.** Sign up on the site, then run:
   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'you@example.com'
   on conflict do nothing;
   ```

## Customising the event

Edit the `EVENT` object in `index.html`: name, tagline, dates, venue, tracks, timeline, prizes, judging weights and FAQ. Setting `dateISO` (for example `"2026-12-05T09:00:00+05:30"`) turns on the countdown.

## Project layout

```
index.html            the whole frontend (markup, styles, logic)
supabase_schema.sql   tables, constraints, trigger and RLS policies
README.md
```

## Known limitations and next steps

- The organizer dashboard (`admin.html`, linked from the footer) is not included yet. The database already supports it through the `admins` table and its policies.
- Email delivery uses Supabase's default sender, which is rate-limited. A custom SMTP provider is recommended for real traffic.
- Adding CAPTCHA (Supabase supports hCaptcha and Turnstile) would further reduce signup abuse.
- A custom backend would let you rate-limit signups and hide the project URL. That's a real option, though not needed for the current scale.

## What this project demonstrates

- Designing a secure data model with Postgres RLS, constraints and triggers, rather than relying on client-side checks
- Threat-thinking: identifying privilege-escalation paths (self-approval, identity spoofing, post-approval edits) and closing them in the database
- Shipping a polished, themed UI in dependency-free JavaScript
- Choosing tools by what the problem needs, and being able to explain the trade-offs

