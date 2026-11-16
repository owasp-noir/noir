import { exec } from 'child_process';

export interface Runner {
  run(q: string): unknown;
}

export class RunnerA implements Runner {
  run(q: string) {
    return exec('echo ' + q);
  }
}

export class RunnerB implements Runner {
  run(q: string) {
    return exec('echo ' + q);
  }
}
