import json
import sys

from beancount import loader
from beancount.core import data

accounts = set()
currencies = set()
events = set()
links = set()
payees = set()
tags = set()

entries, errors, options_map = loader.load_file(sys.argv[1])
for index, entry in enumerate(entries):
    if isinstance(entry, data.Open):
        accounts.add(entry.account)
        if entry.currencies:
            currencies.update(entry.currencies)
    elif isinstance(entry, data.Close):
        accounts.remove(entry.account)
    elif isinstance(entry, data.Commodity):
        currencies.add(entry.currency)
    elif isinstance(entry, data.Event):
        events.add(entry.type)
    elif isinstance(entry, data.Transaction):
        if entry.tags:
            tags.update(entry.tags)
        if entry.links:
            links.update(entry.links)
        # if entry.payee:
        #     payees.add(entry.payee)

for var in ("accounts", "currencies", "events", "links", "payees", "tags"):
    val = sorted(globals()[var])
    encoded = repr(val)
    print(json.dumps(["ex", f"let b:beancount_{var} = {encoded}"]))
print(json.dumps(["ex", "let b:beancount_loaded = v:true"]))
