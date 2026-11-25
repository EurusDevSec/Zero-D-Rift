"""Zero D-Rift BatchTrainingJob reference workload (SPEC-P6 P6-T2.1).

One image, entry points ``submit``, ``train``, ``cleanup`` and ``probe``.
Every object of one run attempt lives under ``runs/<requestId>/<runAttempt>/``
in the tenant's checkpoint bucket; a new attempt never reads another attempt.
"""

__version__ = "0.1.0"
