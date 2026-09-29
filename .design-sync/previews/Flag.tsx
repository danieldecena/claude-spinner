import { Flag } from 'app-kit';

export const Tones = () => (
  <div className="dc-stack" style={{ alignItems: 'flex-start' }}>
    <Flag tone="warn">Card is 94% full. Offload before the next shoot.</Flag>
    <Flag tone="bad">Sync failed: iCloud quota reached.</Flag>
    <Flag tone="accent">3 clips need a keep-or-delete call.</Flag>
  </div>
);
