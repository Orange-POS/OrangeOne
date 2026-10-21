"""Trusted release identities; never accept arbitrary candidate bundle identifiers."""
import os

BUNDLES = {
    'development': 'ch.orangepos.productscanner.dev',
    'staging': 'ch.orangepos.productscanner.stg',
    'production': 'ch.orangepos.productscanner',
}


def bundle_id(flavor=None):
    flavor = os.environ.get('RELEASE_FLAVOR', 'production') if flavor is None else flavor
    if flavor not in BUNDLES:
        raise ValueError('Unsupported release flavor.')
    return BUNDLES[flavor]
