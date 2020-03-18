"""
Tap configuration related stuff
"""
from voluptuous import Schema, Required, Optional, Any

CONFIG_CONTRACT = Schema([{
    Required('table_name'): str,
    Required('search_pattern'): str,
    Optional('key_properties'): [str],
    Optional('search_prefix'): str,
    Optional('date_overrides'): [str],
    Optional('delimiter'): str,
    Optional('default_datatype'): Any('string',
                                      'integer',
                                      'number',
                                      'date-time'),
    Optional('schema_overrides'): [
        {
            Required('column_name'): str,
            Required('conversion_type'): Any('string',
                                             'integer',
                                             'number',
                                             'date-time')
        }
    ],
    Optional('sample_rate'): int,
    Optional('max_records'): int
}])
