#!/usr/bin/env python3
"""Run historical SwiftData migration checks for the Step12Remediation report."""
from historical_store_checks import run


if __name__ == '__main__':
    run('Step12Remediation')
