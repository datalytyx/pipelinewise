"""
Module to guess csv columns' types and build Json schema.
"""
import csv
import io

from typing import Dict, List

import dateutil
import pytz
from messytables import CSVTableSet, headers_guess, headers_processor, offset_processor, type_guess
from messytables.types import DecimalType, IntegerType


def convert(datum, override_type=None):
    """
    Returns tuple of (converted_data_point, json_schema_type,).
    """
    if datum is None or datum == '':
        return None, None,

    if override_type in (None, 'integer'):
        try:
            to_return = int(datum)
            return to_return, 'integer',
        except (ValueError, TypeError):
            pass

    if override_type in (None, 'number'):
        try:
            to_return = float(datum)
            return to_return, 'number',
        except (ValueError, TypeError):
            pass

    if override_type == 'date-time':
        try:
            to_return = dateutil.parser.parse(datum)

            if(to_return.tzinfo is None or
               to_return.tzinfo.utcoffset(to_return) is None):
                to_return = to_return.replace(tzinfo=pytz.utc)

            return to_return.isoformat(), 'date-time',
        except (ValueError, TypeError):
            pass

    return str(datum), 'string',


def count_sample(sample, start=None):
    if start is None:
        start = {}

    for key, value in sample.items():
        if key not in start:
            start[key] = {}

        (_, datatype) = convert(value)

        if datatype is not None:
            start[key][datatype] = start[key].get(datatype, 0) + 1

    return start


def count_samples(samples):
    to_return = None

    for sample in samples:
        to_return = count_sample(sample, to_return)

    return to_return


def pick_datatype(counts):
    """
    If the underlying records are ONLY of type `integer`, `number`,
    or `date-time`, then return that datatype.

    If the underlying records are of type `integer` and `number` only,
    return `number`.

    Otherwise return `string`.
    """
    to_return = 'string'

    if len(counts) == 1:
        if counts.get('integer', 0) > 0:
            to_return = 'integer'
        elif counts.get('number', 0) > 0:
            to_return = 'number'

    elif(len(counts) == 2 and
         counts.get('integer', 0) > 0 and
         counts.get('number', 0) > 0):
        to_return = 'number'

    return to_return


def generate_schema(samples: List[Dict], table_spec: Dict) -> Dict:
    """
    Guess columns types from the given samples and build json schema
    :param samples: List of dictionaries containing samples data from csv file(s)
    :param table_spec: table/stream specs given in the tap definition
    :return: dictionary where the keys are the headers and values are the guessed types - compatible with json schema
    """
    schema = {}
    counts = count_samples(samples)
    default_datatype = table_spec.get('default_datatype')
    schema_override = {column['column_name']: column['conversion_type'] for column in
                       table_spec.get('schema_overrides', [])}
    for key, value in counts.items():
        if default_datatype:
            datatype = default_datatype
        else:
            datatype = pick_datatype(value)

        if datatype == 'date-time':
            schema[key] = {
                'type': ['null', 'string'],
                'format': 'date-time',
            }
        else:
            schema[key] = {
                'type': ['null', datatype],
            }
        if key in schema_override.keys():
            schema[key] = {'type': ['null', schema_override[key]]}

    return schema


def _csv2bytesio(data: List[Dict]) -> io.BytesIO:
    """
    Converts a list of dictionaries to a csv BytesIO which is a csv file like object
    :param data: List of dictionaries to turn into csv like structure
    :return: BytesIO, a file like object in memory
    """
    with io.StringIO() as sio:

        header = set()

        for datum in data:
            header.update(list(datum.keys()))

        writer = csv.DictWriter(sio, fieldnames=header)

        writer.writeheader()
        writer.writerows(data)

        return io.BytesIO(sio.getvalue().strip('\r\n').encode('utf-8'))
