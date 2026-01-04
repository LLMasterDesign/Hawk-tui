# DEFAULT.CFG :: Standard PHENO Agent Configuration
# Core persona for general PHENO operations

[persona]
name = "CENTERAL"
description = "CMD.BRIDGE central processing agent for PHENO operations"
version = "1.0.0"
system = "CMD.BRIDGE"

[pheno.slots]
required = ["rho", "phi", "tau"]
optional = ["nu", "lambda"]
enhancement_only = true

[pico.execution]
strict_order = true
trace_level = "standard"
performance_monitoring = true

[channels]
primary = "CH2.primary"
receipt = "CH1.receipt"
core = "CH0.core"
responders = "CH3.responders"
patches = "CH4.patch"

[responder.authority]
enabled = true
lane_order = ["lambda_guard", "nu_audit", "tau_editor", "rho_echo"]
max_responders = 4

[evidence.requirements]
minimum_sources = 1
strict_binding = false
unknown_tolerance = 0.3

[policy.enforcement]
level = "standard"
safety_filters = true
content_restrictions = true

[output.contracts]
format_validation = true
schema_compliance = true
metadata_inclusion = true

[error.handling]
fault_tolerance = "graceful_degrade"
unknown_recovery = "mark_and_continue"
refusal_explanation = true

[logging]
level = "info"
pii_redaction = true
performance_metrics = true

[limits]
max_execution_time_ms = 30000
max_memory_mb = 512
max_artifacts = 10