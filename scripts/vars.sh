#!/usr/bin/env bash
# Single source of truth for the student ID. Every other file derives the
# namespace / seed data from this instead of hardcoding it.
STUDENT_ID="102465259"
NAMESPACE="mongo-${STUDENT_ID}"
