# Testing harness test inventory

The [testing harness](../tools/test.py) discovers **157 test methods across 18 modules** using Python `unittest` discovery in `tests/` (the default `test*.py` pattern). The inventory below lists every discovered method, grouped by module and test class. The suite includes host unit tests, native instruction-level integration tests and regression tests; the harness does not assign separate unit/regression labels.

This is an inventory of what the harness runs, not a record of a new test execution. Subtests, input loops and fuzz iterations are included in their parent method rather than counted as separate tests. There are currently no explicitly skipped tests.

## Running the harness

From the repository root, with Python 3.10 or newer, the cc65 toolchain and py65 1.2.0 available:

```sh
python3 tools/bootstrap.py  # Optional: install the pinned local tools.
python3 tools/build.py
python3 tools/test.py
```

The harness adds `host/`, `tests/` and `.tools/py65/` to its import path. Native tests use instruction-level py65 execution with deterministic KERNAL stubs. Cartridge-format tests inspect both `build/` and `dist/`; keep the cartridge ROM/CRT in `dist/` synchronized with the current build as described in the [README](../README.md#project-files). These checks do not replace full VICE or physical PAL/NTSC validation.

Before discovery, the harness calls [`check_runtime.check()`](../tools/check_runtime.py) to validate documented opcodes and static dependency closures for the resident runtime, bank-2 ROM services and common-RAM service/editor stubs. It checks allowed calls and memory references, bank-call descriptors and instruction boundaries. A preflight failure stops the harness before tests run.

After the suite finishes, the harness writes `build/test-report.json` with the test, failure, error and skip counts, resident-runtime instruction count, ROM SHA-256 and environment description. It exits with status 0 when the suite succeeds and 1 when it reports failures or errors.

## Coverage summary

| Module | Coverage | Test methods |
| --- | --- | ---: |
| [test_banking.py](../tests/test_banking.py) | Cartridge banking | 8 |
| [test_cartridge.py](../tests/test_cartridge.py) | Cartridge format | 1 |
| [test_cli.py](../tests/test_cli.py) | Command-line interface | 1 |
| [test_collection.py](../tests/test_collection.py) | Garbage collection | 4 |
| [test_design_formatting.py](../tests/test_design_formatting.py) | Design document formatting | 3 |
| [test_editor.py](../tests/test_editor.py) | Command and split screen editors | 36 |
| [test_file_arguments.py](../tests/test_file_arguments.py) | File command arguments | 5 |
| [test_formatting.py](../tests/test_formatting.py) | Source formatting | 4 |
| [test_integer_design.py](../tests/test_integer_design.py) | Integer specification regressions | 6 |
| [test_list_break.py](../tests/test_list_break.py) | Interruptible LIST | 2 |
| [test_native.py](../tests/test_native.py) | Native compiler and runtime | 8 |
| [test_platform.py](../tests/test_platform.py) | Platform and language integration | 24 |
| [test_prg.py](../tests/test_prg.py) | Stock BASIC PRG import | 11 |
| [test_reserve.py](../tests/test_reserve.py) | Reserved RAM and gameplay | 5 |
| [test_revision05.py](../tests/test_revision05.py) | Revision 0.5 regressions | 13 |
| [test_services.py](../tests/test_services.py) | Banked services and gateways | 7 |
| [test_source.py](../tests/test_source.py) | Host tokenizer and source containers | 11 |
| [test_unsigned.py](../tests/test_unsigned.py) | Unsigned integer regressions | 8 |
| **Total** | | **157** |

## Complete test inventory

### Cartridge banking (8)

Source: [test_banking.py](../tests/test_banking.py). PLA visibility, boot image copies, bank/CPU-state preservation, IRQ/NMI handling, KERNAL gates, SYS/USR mapping recovery and warm starts.

**`BankingTests`**

- `test_boot_copies_exact_images`
- `test_copy_preserves_bank_full_port_and_flags`
- `test_irq_restores_nonzero_bank`
- `test_kernal_gate_restores_nonzero_bank`
- `test_latch_and_pla_visibility`
- `test_nmi_during_image_copy`
- `test_sys_usr_restore_bank_after_user_mapping_change`
- `test_warm_header_recovers_from_auxiliary_bank`

### Cartridge format (1)

Source: [test_cartridge.py](../tests/test_cartridge.py). Magic Desk 64 KiB CRT headers, eight bank packets, signatures and exact ROM reconstruction for both build and dist artifacts.

**`CartridgeTests`**

- `test_magic_desk_64kb_layout`

### Command-line interface (1)

Source: [test_cli.py](../tests/test_cli.py). Native run exit status when normal program output resembles an error.

**`CLITests`**

- `test_native_run_exit_status_does_not_mistake_output_for_error`

### Garbage collection (4)

Source: [test_collection.py](../tests/test_collection.py). Captured Void Runner heap replay and cycle budget, allocation/window boundaries, free-list edge cases and automatic collection with live arrays/functions.

**`CollectionTests`**

- `test_automatic_score_string_collection_keeps_arrays_and_functions`
- `test_captured_voidrunner_heap_matches_completed_old_collector`
- `test_empty_free_list_and_full_word_allocation_sizes`
- `test_shared_low_bytes_and_payload_crossing_window_boundary`

### Design document formatting (3)

Source: [test_design_formatting.py](../tests/test_design_formatting.py). Editable Word tables, links and inline notation; literal code preservation; ordered-list numbering and repeatable regeneration.

**`DesignFormattingTests`**

- `test_literal_code_preserves_indentation_and_operators`
- `test_separate_ordered_lists_restart_and_regeneration_reuses_definitions`
- `test_tables_links_and_inline_notation_become_word_content`

### Command and split screen editors (36)

Source: [test_editor.py](../tests/test_editor.py). Submission and output layout, source editing, focus, modes, help, scrolling, selection, F3 navigation, error recovery and runtime-state preservation.

**`EditorTests`**

- `test_command_output_and_submission_errors_start_after_enter`
- `test_console_api_preserves_program_newlines_without_echoing_enter`
- `test_enter_advances_after_numbered_entry_deletion_and_empty_input`

**`SplitEditorTests`**

- `test_bidirectional_scroll_moves_rows_without_touching_color_ram`
- `test_direct_input_uses_bounded_pane_and_retains_command_on_error`
- `test_error_returns_to_command_start_at_its_current_screen_row`
- `test_errors_retain_source_and_put_cursor_at_line_start`
- `test_exact_keywords_do_not_reserve_variable_names`
- `test_f3_go_line_is_incremental_and_non_digits_only_cancel_the_prompt`
- `test_f3_while_collecting_input_preserves_runtime_fields_and_draft`
- `test_failed_load_and_allocation_keep_editable_source`
- `test_focus_copy_and_source_preserving_commands_do_not_redraw_listing`
- `test_focus_switch_discards_draft_and_commands_have_no_ready`
- `test_four_row_capacity_and_scrolling_from_a_direct_output_position`
- `test_go_line_and_submission_keep_wrapped_context_and_destination_visible`
- `test_go_line_visible_destination_only_changes_number_cells`
- `test_help_preserves_a_suspended_gosub_for_cont`
- `test_help_restores_draft_screen_and_bookmarks`
- `test_help_uses_petscii_95_and_restores_saved_listing_without_formatting`
- `test_input_uses_independent_literal_and_overwrite_modes`
- `test_insert_overwrite_literal_and_bounded_cursor`
- `test_lines_taller_than_the_frame_scroll_without_overlap_or_color_writes`
- `test_many_scrolls_and_source_changes_match_fresh_viewports`
- `test_numbered_submissions_select_affected_lines_and_scroll_into_view`
- `test_open_copy_submit_delete_and_exit`
- `test_output_gate_preserves_registers_flags_and_user_zero_page`
- `test_output_scrolls_only_four_rows_and_mutations_refresh_listing`
- `test_overlong_imported_line_is_not_silently_truncated`
- `test_pane_clear_controls_do_not_discard_a_failed_command`
- `test_previous_visible_commands_and_wrapped_lines_can_be_edited`
- `test_run_exits_clears_and_executes`
- `test_scrolls_five_source_lines_and_preserves_bookmarks`
- `test_selection_highlights_only_digits_and_never_reformats_source`
- `test_unchanged_numbered_submission_can_move_only_number_highlights`
- `test_wrapped_scroll_restores_partial_lines_and_matches_a_fresh_view`
- `test_wrapped_source_aligns_past_number_and_controls_are_literal`

### File command arguments (5)

Source: [test_file_arguments.py](../tests/test_file_arguments.py). Optional secondary addresses, single evaluation, statement boundaries and rejection of malformed arguments before opening or changing files.

**`FileArgumentTests`**

- `test_arguments_are_evaluated_once_and_colon_else_boundaries_work`
- `test_invalid_secondary_rejected_before_io`
- `test_malformed_load_and_verify_do_not_publish_or_open`
- `test_malformed_save_does_not_create_or_overwrite_file`
- `test_optional_secondary_roundtrip_and_sequential_channel`

### Source formatting (4)

Source: [test_formatting.py](../tests/test_formatting.py). Canonical host/target listing, source round trips, TAB/SPC calls, abbreviations and identifier boundaries.

**`FormattingTests`**

- `test_host_and_target_canonical_listing_and_roundtrip`
- `test_host_punctuated_abbreviations_and_name_boundaries`
- `test_imported_spaced_calls_execute_and_list_compactly`
- `test_spaced_tab_spc_execute_without_array_bindings`

### Integer specification regressions (6)

Source: [test_integer_design.py](../tests/test_integer_design.py). Literal typing, destination-independent evaluation, declared values, POKE address bits, arithmetic lowering and recompilation after SAVE/CLEAN.

**`IntegerDesignTests`**

- `test_declared_values_and_functions_do_not_become_constant_literals`
- `test_literal_context_is_local_and_destination_independent`
- `test_power_lowering_matches_generic_typed_arithmetic`
- `test_saved_and_cleaned_source_recompiles_with_new_types`
- `test_specification_constants_and_destinations`
- `test_unsigned_literals_do_not_change_poke_address_bits`

### Interruptible LIST (2)

Source: [test_list_break.py](../tests/test_list_break.py). RUN/STOP and pending-break cancellation in stock and split editors.

**`ListBreakTests`**

- `test_pending_break_aborts_before_printing_the_next_line`
- `test_stop_aborts_listing_in_stock_and_split_editors`

### Native compiler and runtime (8)

Source: [test_native.py](../tests/test_native.py). Boot budgets, word arithmetic, POKE, IF/forward anchors, GOSUB/FOR/CONT, strings and deterministic/random program edits.

**`NativeTests`**

- `test_boot_and_budgets`
- `test_gosub_for_cont`
- `test_if_and_forward_anchor`
- `test_random_edits`
- `test_replace_delete_layout`
- `test_required_poke_examples`
- `test_strings`
- `test_word_semantics`

### Platform and language integration (24)

Source: [test_platform.py](../tests/test_platform.py). Memory maps, interrupts, machine-code calls, file rollback, arrays/functions, collection roots, device I/O, control flow, clock handling and allocator boundaries.

**`PlatformTests`**

- `test_arrays_functions_and_clear`
- `test_bad_binary_source_rollback`
- `test_bounded_recursive_function`
- `test_clock_setter_and_wrapped_ti`
- `test_cold_start_initializes_language_zero_page`
- `test_common_allocations_never_cross_the_cartridge_window`
- `test_data_read_spelling`
- `test_failed_edit_preserves_source`
- `test_files_roundtrip_crc_and_rollback`
- `test_for_variable_reuse`
- `test_frozen_control_stack_boundary`
- `test_gc_roots_and_code_stationarity`
- `test_io_input_and_channels`
- `test_irq_and_nmi_frames`
- `test_long_imported_names`
- `test_nested_if_false_and_syntax_stub`
- `test_numeric_get_rejects_nondigits`
- `test_open_defaults_and_excluded_devices`
- `test_payloads_preserve_common_arena_space`
- `test_read_array_targets`
- `test_runtime_refresh`
- `test_shadow_execution_and_io`
- `test_shifted_keyword_abbreviation`
- `test_sys_usr_map_recovery`

### Stock BASIC PRG import (11)

Source: [test_prg.py](../tests/test_prg.py). Token conversion, stock identifier rules, preserved literals/comments, native execution, malformed-input rollback, memory limits and editor integration.

**`PrgImportTests`**

- `test_allocation_failure_preserves_old_program`
- `test_compact_stock_tokens_compile_and_export_as_native_source`
- `test_empty_import_clears_editor_listing_for_both_source_formats`
- `test_empty_program_and_unsupported_numeric_source_remain_editable`
- `test_import_from_editor_keeps_hooks_and_updates_listing`
- `test_prg_can_end_exactly_at_the_stock_basic_memory_limit`
- `test_quotes_rem_data_controls_and_go_to_are_preserved`
- `test_relational_pairs_functions_arrays_and_control_flow`
- `test_stock_get_hash_becomes_the_native_device_keyword`
- `test_stock_name_significance_and_signed_integer_namespace`
- `test_truncation_links_order_tokens_and_trailing_payload_roll_back`

### Reserved RAM and gameplay (5)

Source: [test_reserve.py](../tests/test_reserve.py). Allocator/collector exclusion, reservation validation and lifecycle, declaration scope, source loading and Void Runner gameplay entry.

**`ReserveTests`**

- `test_boundaries_repeats_conflicts_and_new`
- `test_reservations_exclude_user_bytes_from_allocator_and_collector`
- `test_source_load_accepts_empty_string_and_data_text`
- `test_table_limit_and_declaration_scope`
- `test_voidrunner_paste_and_source_load_reach_native_gameplay`

### Revision 0.5 regressions (13)

Source: [test_revision05.py](../tests/test_revision05.py). Resident compiler protection, failed submissions, LIST bounds, ELSE, random numbers, shifts, arithmetic lowering, transactional CLEAN and source tokens.

**`Revision05Tests`**

- `test_arithmetic_shifts_precedence_and_checked_counts`
- `test_clean_allocation_failure_rolls_back_and_cleans_transport`
- `test_clean_empty_and_malformed_source`
- `test_clean_failure_reclaims_staged_array_and_function_records`
- `test_clean_rebuilds_dense_slabs_symbols_and_refs`
- `test_else_branches_nesting_colons_and_line_targets`
- `test_list_bounds_and_newline`
- `test_new_tokens_roundtrip_in_source_container`
- `test_power_of_two_lowering_preserves_division`
- `test_resident_compiler_image_is_reserved_and_survives_collection`
- `test_rng_full_word_reseed_and_repeat`
- `test_rng_initial_seed_uses_clock_once`
- `test_submission_reports_failure_and_retains_source`

### Banked services and gateways (7)

Source: [test_services.py](../tests/test_services.py). Stub installation, register/flag/port/bank/stack preservation, nested calls, blocking input, interrupts, inline operands and shadow-RAM data.

**`ServiceTests`**

- `test_blocking_input_keeps_irqs_enabled_and_resumes_bank_frames`
- `test_boot_installs_stubs_after_page_three_clear`
- `test_data_spelling_in_shadow_ram_and_service_errors`
- `test_definition_activation_reads_inline_operands_under_rom`
- `test_interrupts_at_nested_transition_boundaries`
- `test_nested_rom_ram_and_kernal_calls`
- `test_registers_flags_full_port_bank_and_stack`

### Host tokenizer and source containers (11)

Source: [test_source.py](../tests/test_source.py). Vocabulary, identifier boundaries, canonical listing, transactional tokenization, CRC, dense names, empty containers, malformed data and decoder fuzzing.

**`ContainerTests`**

- `test_corruption_and_truncation`
- `test_crc_known_vector`
- `test_empty`
- `test_fuzz_safe_decoder`
- `test_roundtrip_dense_names`

**`TokenTests`**

- `test_canonical_list`
- `test_every_word`
- `test_name_boundaries`
- `test_reject_malformed`
- `test_transactional_tokenization`
- `test_worked_examples`

### Unsigned integer regressions (8)

Source: [test_unsigned.py](../tests/test_unsigned.py). Bit-preserving assignments, arithmetic and comparisons, signed mixing, arrays/functions/I/O, FOR limits, FRE/CONT, collection roots and long names.

**`UnsignedTests`**

- `test_arrays_data_input_functions_and_clean`
- `test_bit_preserving_assignments_and_full_names`
- `test_empty_fre_unsigned_and_continuation_preservation`
- `test_random_unsigned_division_and_comparisons`
- `test_source_import_and_255_byte_unsigned_name`
- `test_unsigned_arithmetic_and_signed_mixing`
- `test_unsigned_for_boundaries`
- `test_unsigned_stack_and_array_values_are_not_string_roots`

## Maintaining this inventory

When test methods or discovery rules change, update the module counts and method lists here. Use the module, class and method names together to identify each test (for example, `test_banking.BankingTests.test_boot_copies_exact_images`). Consult `build/test-report.json` for the outcome of a particular harness run.
