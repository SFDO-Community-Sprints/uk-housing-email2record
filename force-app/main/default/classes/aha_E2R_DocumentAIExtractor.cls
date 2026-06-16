/**
 * aha_E2R_DocumentAIExtractor
 *
 * POC: extracts structured data from the PDF/image File attached to an aha_E2R_Record__c using
 * Data 360 Document AI's real-time `extract-data` Connect API, then writes the result back onto
 * the record (aha_Doc_Type__c, aha_Doc_Summary__c).
 *
 * Modeled on the official "Automate Resume Processing with Document AI" guide
 * (developer.salesforce.com/docs/ai/automate-resume-processing), adapted to run against the file
 * already attached by aha_E2R_EmailParser instead of a quick-action upload.
 *
 * Uses the SAVED Document AI schema config (built in the UI) by passing `idpConfigurationIdOrName`,
 * and references the file by `fileId` (its ContentVersion Id) — so NO base64, NO UDLO, and NO
 * blob-store ingestion are required.
 *
 * ── PREREQUISITES (org) ──
 *  1. Named Credential `aha_DocumentAI` (+ its External Credential) pointing at this org's My Domain,
 *     authorised to call the Connect API. Endpoint becomes callout:aha_DocumentAI/...
 *  2. IDP_CONFIG_NAME below set to YOUR saved Document AI config's API name.
 *  3. A PDF/image File attached to the record (aha_E2R_EmailParser does this for inbound email).
 *
 * ── INVOCATION ──
 *  Designed for synchronous, user-initiated invocation (the `aha E2R Record Panel` screen flow or a
 *  record button) — Apex callouts are allowed there. For an email-arrival auto-trigger, wrap
 *  extractAndUpdate() in a Queueable/@future (callouts can't run inline in the email handler).
 */
public with sharing class aha_E2R_DocumentAIExtractor {

    // ── Configuration (adjust to your org) ──
    private static final String API_VERSION   = 'v63.0'; // extract-data version per the Document AI guide
    private static final String NAMED_CRED     = 'callout:aha_DocumentAI';
    private static final String EXTRACT_PATH   =
        '/services/data/' + API_VERSION + '/ssot/document-processing/actions/extract-data?htmlEncode=false';
    /** API name of YOUR saved Document AI schema config (the 2-field POC config). */
    private static final String IDP_CONFIG_NAME = 'DocumentAIReadDoc';

    // Response field keys = the property API names in your saved config. Adjust if they differ.
    private static final String KEY_DOC_TYPE = 'documentType';
    private static final String KEY_SUMMARY  = 'summary';

    private static final Set<String> SUPPORTED_EXT =
        new Set<String>{ 'pdf', 'png', 'jpg', 'jpeg'};

    // ──────────────────────────────── Entry points ────────────────────────────────

    public class Request {
        @InvocableVariable(label='E2R Record Id' required=true) public Id recordId;
        @InvocableVariable(label='Config API Name (optional override)') public String configName;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Extracted Data (JSON)') public String extractedDataJson;
    }

    @InvocableMethod(label='Extract Document Data (E2R)'
                     description='Extract data from the attached PDF/image via Document AI and update the E2R Record'
                     category='Document AI')
    public static List<Result> extract(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(extractAndUpdate(req.recordId, req.configName));
        }
        return results;
    }

    /** Reusable core: find attached file → call Document AI with the saved config → update record. */
    public static Result extractAndUpdate(Id recordId, String configNameOverride) {
        Result r = new Result();
        try {
            ContentVersion cv = getLatestSupportedFile(recordId);
            if (cv == null) {
                r.success = false;
                r.message = 'No supported PDF/image file is attached to the record.';
                return r;
            }

            String configName = String.isBlank(configNameOverride) ? IDP_CONFIG_NAME : configNameOverride;
            String rawJson = callExtractData(cv.Id, configName);
            r.extractedDataJson = rawJson;

            Map<String, Object> fields = extractFieldsMap(rawJson);

            aha_E2R_Record__c rec = new aha_E2R_Record__c(Id = recordId);
            rec.aha_Doc_Type__c    = readValue(fields, KEY_DOC_TYPE);
            rec.aha_Doc_Summary__c = readValue(fields, KEY_SUMMARY);
            update rec;

            r.success = true;
            r.message = 'Extracted and updated from "' + cv.Title + '".';
        } catch (Exception e) {
            r.success = false;
            r.message = e.getMessage();
        }
        return r;
    }

    // ──────────────────────────────── Document AI callout ────────────────────────────────

    /** POST extract-data referencing the saved config by name and the file by ContentVersion Id. */
    private static String callExtractData(Id contentVersionId, String configName) {
        Map<String, Object> body = new Map<String, Object>{
            'idpConfigurationIdOrName' => configName,
            'files' => new List<Object>{ new Map<String, String>{ 'fileId' => contentVersionId } }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CRED + EXTRACT_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new DocumentAIException('Document AI extract-data error: '
                + res.getStatusCode() + ' - ' + res.getBody());
        }
        return res.getBody();
    }

    // ──────────────────────────────── Response parsing ────────────────────────────────

    /**
     * Normalises the extract-data response into a flat map of {fieldName -> value-or-{value:...}}.
     * Tolerates the response shapes seen across versions: data as a List of results (each possibly
     * wrapping its payload in an inner "data" JSON string) or data as a Map.
     */
    @TestVisible
    private static Map<String, Object> extractFieldsMap(String responseBody) {
        Map<String, Object> top = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Object dataNode = top.containsKey('data') ? top.get('data') : top;

        if (dataNode instanceof List<Object>) {
            List<Object> dataList = (List<Object>) dataNode;
            if (dataList.isEmpty()) return new Map<String, Object>();
            dataNode = dataList[0];
        }

        if (dataNode instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) dataNode;
            // Some responses nest the extracted JSON as a string under "data".
            if (m.get('data') instanceof String) {
                String innerJson = ((String) m.get('data')).replace('&quot;', '"').replace('&#92;', '\\');
                return (Map<String, Object>) JSON.deserializeUntyped(innerJson);
            }
            return m;
        }
        return new Map<String, Object>();
    }

    /** A field may be flat ("value") or an object {value, confidence_score}; handle both. */
    private static String readValue(Map<String, Object> fields, String key) {
        Object v = fields.get(key);
        if (v == null) return null;
        if (v instanceof Map<String, Object>) {
            Object fieldVal = ((Map<String, Object>) v).get('value');
            return fieldVal == null ? null : String.valueOf(fieldVal);
        }
        return String.valueOf(v);
    }

    // ──────────────────────────────── Helpers ────────────────────────────────

    private static ContentVersion getLatestSupportedFile(Id recordId) {
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :recordId
        ]) {
            docIds.add(link.ContentDocumentId);
        }
        if (docIds.isEmpty()) return null;

        List<ContentVersion> cvs = [
            SELECT Id, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
              AND FileExtension IN :SUPPORTED_EXT
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return cvs.isEmpty() ? null : cvs[0];
    }

    public class DocumentAIException extends Exception {}
}