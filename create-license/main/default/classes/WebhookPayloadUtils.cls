public class WebhookPayloadUtils {
    public static Date parseDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            if (dateString.contains('T')) {
                dateString = dateString.substringBefore('T');
            }
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WebhookPayloadUtils: failed to parse date');
            return null;
        }
    }
}
