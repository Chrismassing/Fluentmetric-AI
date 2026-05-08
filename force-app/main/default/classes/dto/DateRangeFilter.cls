/**
 * Reusable date-range input for every dashboard query.
 * startDate and endDate are inclusive of the filter.
 */
public with sharing class DateRangeFilter {
    @AuraEnabled
    public DateTime startDate;
    @AuraEnabled
    public DateTime endDate;

    public DateRangeFilter() {
    }

    public DateRangeFilter(DateTime startDate, DateTime endDate) {
        this.startDate = startDate;
        this.endDate = endDate;
    }

    public static DateRangeFilter lastNDays(Integer n) {
        return new DateRangeFilter(DateTime.now().addDays(-n), DateTime.now());
    }
}
