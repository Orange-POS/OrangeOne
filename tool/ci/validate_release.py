"""Fail closed before a manual distribution job receives protected secrets."""
import os
import re


def validate(values):
    if values.get('GITHUB_REF') != 'refs/heads/main' or values.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        raise ValueError('Distribution must be manually dispatched from main.')
    if not re.fullmatch(r'\d+\.\d+\.\d+', values.get('RELEASE_VERSION', '')):
        raise ValueError('Version must have three numeric components, e.g. 1.0.0.')
    if not re.fullmatch(r'[1-9]\d{0,3}', values.get('RELEASE_BUILD_NUMBER', '')):
        raise ValueError('Use a unique build integer from 1 to 9999.')
    operation = values.get('OPERATION')
    if operation not in ('testflight', 'submit_for_review'):
        raise ValueError('Unsupported release operation.')
    if operation == 'submit_for_review' and values.get('IPHONE_SMOKE_TEST_CONFIRMED') != 'true':
        raise ValueError('Complete the physical iPhone smoke checklist before submission.')


if __name__ == '__main__':
    try:
        validate(os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None
