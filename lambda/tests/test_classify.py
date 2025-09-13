from handler import classify_doc_type

def test_activity():
    assert classify_doc_type("acme-activity-2025.csv") == "daily-activity"

def test_balance():
    assert classify_doc_type("BALANCE_report.csv") == "daily-balance"

def test_default():
    assert classify_doc_type("unknown.txt") == "daily-activity"
