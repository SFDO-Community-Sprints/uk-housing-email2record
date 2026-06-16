/**
 * aha_E2R_DocumentAIQueueable
 *
 * Async wrapper so Document AI extraction runs AFTER the inbound-email transaction commits.
 * Apex cannot make a callout in the same transaction that performed DML (the email parser inserts
 * the record + file), so aha_E2R_EmailParser enqueues this job instead of calling the extractor
 * inline. By the time it runs, the file and its ContentDocumentLink are committed.
 */
public with sharing class aha_E2R_DocumentAIQueueable implements Queueable, Database.AllowsCallouts {

    private final Id recordId;

    public aha_E2R_DocumentAIQueueable(Id recordId) {
        this.recordId = recordId;
    }

    public void execute(QueueableContext ctx) {
        aha_E2R_DocumentAIExtractor.Result result =
            aha_E2R_DocumentAIExtractor.extractAndUpdate(recordId, null);
        if (result != null && result.success != true) {
            System.debug(LoggingLevel.ERROR,
                'aha_E2R_DocumentAIQueueable failed for ' + recordId + ': ' + result.message);
        }
    }
}