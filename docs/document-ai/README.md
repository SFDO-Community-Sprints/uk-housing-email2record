# Installing the Document AI Attachment Extension into a New Org

This is an extension on top of the core Email to Record install — it adds the ability to
extract structured data from email **attachments** (PDF / image) in addition to the email body,
using the **Data 360 Document AI** schema configuration `ahaE2RDocumentAIv1`.

> **The Document AI schema configuration is a design artifact, not deployable metadata.** Unlike
> the OBLT (`force-app/main/default/lightningTypes/ahaE2RRecordOBLTv1/schema.json`), it is **not**
> part of the DX source that deploys from `force-app`. It is created in the **Data 360 setup UI**
> (document schema builder) or via the **Data 360 Connect REST API**. Keep
> [`schema.json`](./schema.json) as the versioned source of truth and reproduce it in the org by
> hand (see Step 2 below).


## Prerequisites

- The base **Email to Record** package ([uk-housing-email2record](https://github.com/SFDO-Community-Sprints/uk-housing-email2record))
  must already be installed and working in the target org — this extension builds on top of
  the existing object, flows, and email service rather than replacing them.
- **Einstein / Agentforce** must be enabled (same requirement as the base install).
- **Data Cloud** must be enabled in the org, with **Document AI** available
  (Setup > Data Cloud > Process Content > Document AI) — this extension relies on a Document
  AI schema configuration to extract data from attachments.

## Field types

`schema.json` uses generic types that map onto both the Data 360 schema builder field types and the
`aha_E2R_Record__c` field you create for each:

| Spec `type` | Data 360 builder type | Suggested `aha_*__c` field type |
|-------------|----------------------|--------------------------------|
| `text`      | Text                 | Text / Text Area               |
| `number`    | Number               | Number / Currency              |
| `date`      | Date                 | Date                           |
| `boolean`   | Checkbox / Boolean   | Checkbox                       |

The `description` of each property is **extraction guidance** — it tells the LLM what to look for, so
write it the way you'd brief a person reading the document. The `targetField` is the
`aha_E2R_Record__c` field the value maps to (created in step 3 of the proposal).

## Steps

1. Retrieve/deploy the components listed in `manifest/package-documentai.xml` into your target org:

   ```bash
   sf project deploy start --manifest manifest/package-documentai.xml --target-org <your-alias>
   ```

## Post-Deployment Steps

Complete these in the target org after the deploy above succeeds.

1. Set up the callout to the `extract-data` Connect API. `aha_E2R_DocumentAIExtractor` calls the
   org's own REST API (`/services/data/<version>/ssot/document-processing/actions/extract-data`)
   via `callout:aha_DocumentAI`, so the org needs to authorise a callout to itself:

   1. **Create an External Client App** — Setup → **External Client App Manager** → **New
      External Client App**. Enable OAuth, set a callback URL (e.g. your My Domain login URL),
      and add the `api` scope. Under **Policies**, enable the **Client Credentials Flow** and
      set a **Run As** user (this user's permissions apply to the callout — give it the
      `Document AI PermissionSet`, see step 3 below). Save and note the **Consumer Key** and
      **Consumer Secret**.
   2. **Create an External Credential** — Setup → **Named Credentials** → **External
      Credentials** tab → **New**. Set **Authentication Protocol** to OAuth 2.0 and
      **Authentication Flow Type** to **Client Credentials with Client Id and Secret Flow**.
      Set the **Identity Provider URL** to your org's My Domain login URL
      (`https://<your-domain>.my.salesforce.com/services/oauth2/token`). Add a **Principal**
      and supply the Consumer Key/Secret from step 1.
   3. **Create the Named Credential** — Setup → **Named Credentials** → **New**. Name it
      `aha_DocumentAI` (must match `NAMED_CRED` in `aha_E2R_DocumentAIExtractor.cls`). Set the
      **URL** to your org's My Domain base URL, link the **External Credential** from step 2,
      and enable **Generate Authorization Header**.

2. Build the Document AI schema configuration in Data Cloud (manual, UI-based — not part of
   the DX source):

   1. **Setup → Data 360 (Data Cloud) → Process Content → Document AI → New Schema Configuration.**
   2. Choose **"without a source object"** (we extend via Flow/Apex), select the LLM, and set
      document types to **PDF** and **Image**.
   3. For each property in `schema.json`, add a field: use `title` as the field name, `type` for
      the field type, and paste `description` as the extraction instruction.
   4. Upload a few sample attachments and **test** the extraction; tune descriptions until
      results are reliable.
   5. **Deploy** the configuration.

3. Set the saved config's API name as `IDP_CONFIG_NAME` in
   `aha_E2R_DocumentAIExtractor.cls` — this is how the extractor (enqueued via
   `aha_E2R_DocumentAIQueueable` from `aha_E2R_EmailParser`) knows which configuration to call.

4. Assign the **Document AI PermissionSet** to the running user. The queueable executes as
   whichever user enqueued it — the Email Service's **Run As User** — so that user needs field
   access to `aha_Doc_Type__c` and `aha_Doc_Summary__c` to write the extracted values back to
   the record.

   1. Go to **Setup > Permission Sets**
   2. Open **Document AI PermissionSet**
   3. Click **Manage Assignments > Add Assignment**
   4. Select the Email Service Run As User and save

## Keeping spec and org in sync

When you change a field here, mirror it in the org's schema configuration (and vice versa). Bump the
version suffix (`...v1` → `v2`) for breaking schema changes, matching the OBLT naming convention.

