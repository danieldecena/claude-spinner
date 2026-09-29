import { useState } from 'react';
import { ListRow } from 'app-kit';

const clips = [
  ['DJI_0412', 'Mini 4 Pro, 4K 60', '0:48'],
  ['OSMO_1187', 'Osmo Pocket 3, 4K 30', '2:14'],
  ['C0093', 'Sony a7 IV, 4K 24', '0:31'],
];

export const ClipList = () => {
  const [sel, setSel] = useState(1);
  return (
    <div className="dc-list" role="listbox" aria-label="Clips" style={{ maxWidth: 520 }}>
      {clips.map(([title, subtitle, trailing], i) => (
        <ListRow key={title} title={title} subtitle={subtitle} trailing={trailing} thumb="4K" selected={sel === i} onClick={() => setSel(i)} />
      ))}
    </div>
  );
};
