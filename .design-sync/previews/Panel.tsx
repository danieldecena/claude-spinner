import { Panel, Badge } from 'app-kit';

export const Titled = () => (
  <Panel title="Lake Washington" meta="Updated 6 min ago">
    <p style={{ margin: 0, color: 'var(--ink-soft)' }}>Stocked 2,400 rainbow trout on Sep 12. Best bite at dawn.</p>
    <div className="dc-row">
      <Badge tone="ok">Open</Badge>
      <Badge>Boat launch</Badge>
    </div>
  </Panel>
);
