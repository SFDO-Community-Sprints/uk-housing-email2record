# AHA Email to Record

Converts inbound emails into structured Salesforce records, enriched by an Agentforce Prompt Template. Built for UK Housing; adaptable to any vertical.

## Project Overview

### Vision & Goals

Provide a free, open-source starting point for Salesforce orgs that receive structured information by email and want to turn those emails into actionable Salesforce records automatically — with AI-extracted fields — without custom integration work.

* Route inbound emails to Salesforce records with zero manual data entry
* Use Agentforce Prompt Templates to extract structured data (dates, categories, priorities, summaries) from free-text email bodies
* Remain lightweight and generic enough to adapt to any domain in under an hour

### Project Vertical

Created for UK Housing; adaptable to any vertical.

### Trailblazer Group or Slack Channel

Slack: `#aha-e2r`

### How to Contribute

- Open an issue or pull request on [GitHub](https://github.com/SFDO-Community-Sprints/uk-housing-email2record)
- Join the [Salesforce Open Source Commons](https://trailhead.salesforce.com/trailblazer-community/groups/0F94S000000GwVK)
- Contact the maintainers via GitHub

### Project Resources and Documentation

Full installation and customisation documentation is in this README. See also the repository [wiki](https://github.com/SFDO-Community-Sprints/uk-housing-email2record/wiki) for sprint history and contributor notes.

---

## What It Does

1. An email arrives at a Salesforce Email Service address
2. An Apex handler creates an `aha_E2R_Record__c` record from the email (From, Subject, Body)
3. A record-triggered Flow sends the email body to an Agentforce Prompt Template
4. The LLM extracts structured data (sender name, date, summary, category, priority, action flag, notes) and populates the record fields automatically

***

## Prerequisites

### Enable Agentforce
This solution uses Prompt Templates. Check that your Salesforce org / sandbox has **Einstein / Agentforce** licences (required for Prompt Templates).

- Enable Einstein / Gen AI

> Setup > Einstein Setup > Turn On Einstein

- Check that **Prompt Templates** exist

> App Launcher > Agentforce Studio > Prompt Templates

- Check that the **Salesforce CLI** is installed. [Install guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)

```bash
sf --version
sf --update
# Authenticate and set default org:
sf org login web --alias my-org-alias --set-default
```

***

## Installation

### 1. Clone the repo

If you are only installing (no plans to modify or contribute), use a shallow clone — it downloads only the current files with no history, which is faster and smaller:

```bash
git clone --depth 1 https://github.com/SFDO-Community-Sprints/uk-housing-email2record.git
cd uk-housing-email2record
```

If you plan to customise or contribute, omit `--depth 1` to get the full history:

```bash
git clone https://github.com/SFDO-Community-Sprints/uk-housing-email2record.git
cd uk-housing-email2record
```

### 2. Deploy to your org

Deploy in three steps — order matters due to Salesforce metadata dependencies.

#### Step 1 — Lightning Type

Must exist before the Prompt Template or Flows reference it.

```bash
sf project deploy start --source-dir force-app/main/default/lightningTypes --target-org <your-alias>
```

#### Step 2 — Prompt Template

Must exist before Flows that call it as an action.

```bash
sf project deploy start --source-dir force-app/main/default/genAiPromptTemplates --target-org <your-alias>
```

#### Step 3 — Everything else

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/flows \
  --source-dir force-app/main/default/queues \
  --source-dir force-app/main/default/emailservices \
  --source-dir force-app/main/default/flexipages \
  --source-dir force-app/main/default/layouts \
  --source-dir force-app/main/default/tabs \
  --source-dir force-app/main/default/permissionsets \
  --target-org <your-alias>
```

---

## ⚙️ Post-Deployment Configuration

> Complete all steps below **in the target org** after the three deploy commands above succeed. Do them in order.

### 1. Grant Permissions

A permission set `aha E2R Access` is included and deploys with the package. It grants full Read, Create, Edit, Delete, View All, and Modify All on `aha_E2R_Record__c`, Read/Edit on all 13 fields, and tab visibility. Assign it to users who need access.

1. Go to **Setup > Permission Sets**
2. Open **aha E2R Access**
3. Click **Manage Assignments > Add Assignment**
4. Select the target users and save

Admins may de-scope object or field permissions from the permission set at any time.

### 2. Validate and Activate Prompt Template

The template deploys with settings intact, but must be saved as a new version and activated before it can be invoked by the Flow.

1. Go to **Setup > Prompt Builder**
2. Open **aha E2R Record - Email**
3. Click **Edit** and review all settings — verify the prompt text and that **Response Format / Lightning Object Type** is set to `ahaE2RRecordOBLTv1`
4. Click **Save as New Version**
5. Click **Activate** on the new version

### 3. Activate Flows

Flows deploy as Draft and must be saved as a new version before activating.

1. Go to **Setup > Flows**
2. Open **aha E2R Record - Populate from Email**
   - Click **Edit**
   - Click **Save as New Version**
   - Click **Activate**
3. Open **aha E2R Record Panel**
   - Click **Edit**
   - Click **Save as New Version**
   - Click **Activate**

### 4. Activate the Lightning Record Page

The Lightning page for `aha_E2R_Record__c` deploys but is not set as the org default.

1. Navigate to the **E2R Records** tab and open (or create) any record
2. Click the **Setup (gear) icon** in the top-right > **Edit Page**
3. Click **Save**, then click **Activation**
4. Select **Org Default** and click **Assign as Org Default**
5. Save and close

### 5. Configure Email Service

The Email Service deploys without an address because the `runAsUser` is org-specific.

1. Go to **Setup > Custom Code > Email Services**
2. Open **aha_E2R_Emails**
3. Click **New Email Address**
4. Set **Run As User** to a valid active user in the target org
5. Save and note the generated email address — this is what senders email to create records

**Optional — restrict which senders are accepted:**
On the Email Service record, the **Accept Email From** field can be set to a comma-separated list of email addresses or domains. By default this is empty, meaning all senders are accepted.

---

## Testing End-to-End

Once all post-deployment steps are complete, send the following email to your Email Service address to verify the full flow. It is designed to exercise every field the Prompt Template extracts.

```
To:      <your Email Service address>
Subject: Urgent Repair Required — Roof Leak, 14 Birchwood Close, Flat 3

Dear Repairs Team,

I attended the above property this morning following a referral from your
contact centre. On inspection I found a damaged ridge tile on the rear roof
slope causing water ingress into the bedroom ceiling of Flat 3. The tenant,
Mrs Patel, has reported the leak has been ongoing for approximately two weeks
and there is visible damp staining on the ceiling plasterboard.

The repair needs to be completed before the weekend — further rain is forecast
and the plasterboard will need replacing if water ingress continues.

I can return to site on Friday 22 May 2026 to carry out the full repair,
subject to your works order being raised today. Please confirm by return so I
can arrange materials.

Category: Responsive Repair

Many thanks,
Dave Holloway
Holloway Building & Roofing Contractors
```

After sending, open the **E2R Records** tab in your org. A new record should appear within a few seconds, owned by the `aha_E2R_Records` queue, with all fields populated:

| Field | Expected value |
|-------|---------------|
| Sender Name | Dave Holloway |
| Record Date | 2026-05-22T00:00:00Z (or similar) |
| Summary | 1–2 sentence summary of the roof leak report |
| Category | Responsive Repair |
| Priority | High |
| Action Required | true |
| Notes | Details about Flat 3, Mrs Patel, damp staining, plasterboard risk |

---

## Customising for Your Use Case

This template ships with a minimal, illustrative set of extracted fields. To adapt it to a specific domain:

1. **Object** — add fields to `aha_E2R_Record__c` (or rename the object entirely for your use case)
2. **OBLT** — add properties to `ahaE2RRecordOBLTv1/schema.json` to tell the LLM what new fields to extract
3. **Prompt Template** — update the `<content>` in `aha_E2R_Record_Email.genAiPromptTemplate-meta.xml` to describe your domain and email format
4. **Flows** — add `<inputAssignments>` in `aha_E2R_Record_Populate_from_Email` and `<assignmentItems>` in `aha_E2R_Record_Panel` to map new OBLT properties to new fields
5. **UI** — add new fields to the page layout and flexipage

Redeploy following the three-step order above after any changes (Lightning Type → Prompt Template → everything else).

---

## Components Installed

| Type | Name | Purpose |
|------|------|---------|
| Custom Object | `aha_E2R_Record__c` | Core record |
| Apex Class | `aha_E2R_EmailParser` | Inbound email handler |
| Flow | `aha E2R Record - Populate from Email` | Trigger flow: queue assignment + AI enrichment |
| Flow | `aha E2R Record Panel` | Screen flow: manual re-enrichment from record sidebar |
| Flow | `aha_util_Get_Queue_Id` | Utility: resolves queue ID by name |
| Queue | `aha_E2R_Records` | Owner for new records |
| Prompt Template | `aha E2R Record - Email` | LLM extraction prompt |
| Lightning Type | `ahaE2RRecordOBLTv1` | Structured output schema for the LLM |
| Email Service | `aha_E2R_Emails` | Receives inbound emails |
| Lightning Page | `aha_E2R_Record_Record_Page` | Record page layout |
| Custom Tab | `aha_E2R_Record__c` | Tab for the object |
| Page Layout | `aha_E2R_Record__c-E2R Record Layout` | Field layout for the record |
| Permission Set | `aha E2R Access` | Full object + field + tab access for end users |

---

## Reinstalling

This install is not designed to handle upgrades. Before reinstalling, manually remove the components and then run the installation steps from scratch.

---

## For Maintainers / Contributors

The `ai_scripts/post_retrieve_strip.sh` script and `DEPLOYMENT.md` are maintainer tools — **installers do not need them**. They are used after `sf project retrieve` to strip org-specific data before committing updated source to the repo.

After any retrieve from the source org, run:

```bash
bash ai_scripts/post_retrieve_strip.sh
```

See `DEPLOYMENT.md` for full details on the deploy order rationale and known issues.

---

## Contributing

This is an open source project. Contributions welcome.

- Open an issue or PR on [GitHub](https://github.com/SFDO-Community-Sprints/uk-housing-email2record)
- Join the [Salesforce Open Source Commons](https://trailhead.salesforce.com/trailblazer-community/groups/0F94S000000GwVK)
- Contact the maintainers via GitHub

### Potential Additions

- Process email attachments (text documents, images/scans)
- Handle schema drift gracefully in the prompt
- Installation walkthrough video and illustrated doc
