import { useState } from 'react';
import { FilterPill } from 'app-kit';

export const CameraFilters = () => {
  const [on, setOn] = useState<Record<string, boolean>>({ osmo: true, a7: false, dji: true, flag: false });
  const toggle = (k: string) => setOn({ ...on, [k]: !on[k] });
  return (
    <div className="dc-row">
      <FilterPill selected={on.osmo} count={128} onClick={() => toggle('osmo')}>Osmo Pocket 3</FilterPill>
      <FilterPill selected={on.a7} count={44} onClick={() => toggle('a7')}>Sony a7 IV</FilterPill>
      <FilterPill selected={on.dji} count={9} onClick={() => toggle('dji')}>Mini 4 Pro</FilterPill>
      <FilterPill selected={on.flag} onClick={() => toggle('flag')}>Flagged</FilterPill>
    </div>
  );
};
