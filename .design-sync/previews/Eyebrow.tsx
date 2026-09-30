import { Eyebrow } from 'app-kit';

export const Plain = () => (
  <div className="dc-row" style={{ gap: 24 }}>
    <Eyebrow>Importing</Eyebrow>
    <Eyebrow>Idle</Eyebrow>
  </div>
);

export const Act = () => (
  <div className="dc-row" style={{ gap: 24 }}>
    <Eyebrow act>Blocked</Eyebrow>
  </div>
);
