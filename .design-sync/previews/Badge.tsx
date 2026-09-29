import { Badge } from 'app-kit';

export const Tones = () => (
  <div className="dc-row">
    <Badge>4K 60</Badge>
    <Badge tone="hollow">HLG</Badge>
    <Badge tone="accent">Selected</Badge>
    <Badge tone="ok">Synced</Badge>
    <Badge tone="warn">Stale</Badge>
    <Badge tone="bad">Failed</Badge>
  </div>
);
