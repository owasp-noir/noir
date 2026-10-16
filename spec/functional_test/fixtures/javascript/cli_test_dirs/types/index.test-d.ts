// Type-level test (tsd): not a shipped entry point.
import { program } from 'commander';

program.option('--type-test-only', 'must not become a flag');
