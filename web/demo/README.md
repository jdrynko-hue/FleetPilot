# Flotaryx Ecosystem — staging-only interactive preview

**Demo for iPhone / Safari:** [Open the four-role interactive preview](https://rawcdn.githack.com/jdrynko-hue/FleetPilot/cf84f1a12499cc925b08d35b99b9fef4fbbee71a/web/demo/index.html)

This is a **free third-party read-only HTML preview** pinned to a tested Git commit, not an independent Flotaryx hosting deployment. The provider may display a one-time HTML safety confirmation before opening the page. Do not enter any real customer or vehicle information.

A seven-step guide shows the next role, required action and completion progress.

This preview demonstrates **Fleet → Garage estimate → Fleet approval → mechanic repair → service history**, plus **private customer → booking request → workshop confirmation**. Switch between Fleet, Garage, Mechanic and Customer using the top tabs. All state is held in memory and disappears on reload. No Supabase/API/payment/network calls are made by the demo.

### Release and security constraints

- Keep the preview tied to an immutable test commit; future updates require a new commit-specific URL; **never merge or publish this demo at `flotaryx.com/app/`**.
- The preview URL is publicly accessible because the source repo is public. It is **not confidential staging**.
- No GitHub Pages, Namecheap DNS, live Stripe, hosted Supabase, paid service or actual garage booking is activated.
- The free proxy is meant only for testing. For long-term staging, replace it with a controlled `staging.flotaryx.com` deployment with an explicit access policy and verified host.
