import { useState } from 'react';
import { Toolbar, Button, SegmentedControl } from 'app-kit';

const s = { width: 16, height: 16, viewBox: '0 0 16 16', fill: 'none', stroke: 'currentColor', strokeWidth: 1.5, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const, 'aria-hidden': true };
const tools = [
  { title: 'Import', icon: <svg {...s}><path d="M8 2.5v8M4.5 7 8 10.5 11.5 7M3 13.5h10" /></svg> },
  { title: 'Reveal in Finder', icon: <svg {...s}><path d="M2.5 4.5h4l1.5 1.5h5.5v6.5h-11z" /></svg>, disabled: 'No clip selected' },
];
const rows = ['C0042 dawn, north shore', 'C0043 dawn, launch', 'C0044 midday, dock', 'C0045 dusk, point', 'C0046 dusk, point'];

const Demo = ({ notice }: { notice?: string }) => {
  const [note, setNote] = useState<string | null>(notice ?? null);
  return (
    <div style={{ height: 132, overflow: 'auto', borderRadius: 14, background: 'var(--ground)' }}>
      <Toolbar searchLabel="Search clips" tools={tools} notice={note}
        primary={<Button variant="filled" onClick={() => setNote('Exported 42 clips')}>Export</Button>}>
        <SegmentedControl label="View" options={['Grid', 'List']} defaultValue="Grid" />
      </Toolbar>
      <div style={{ padding: '8px 16px' }}>
        {rows.map((r) => <div key={r} style={{ padding: '6px 0', color: 'var(--ink-soft)' }}>{r}</div>)}
      </div>
    </div>
  );
};

export const Default = () => <Demo />;
export const WithNotice = () => <Demo notice="Exported 42 clips" />;
