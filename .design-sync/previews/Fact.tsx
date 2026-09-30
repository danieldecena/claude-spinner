import { Fact } from 'app-kit';

export const Values = () => (
  <dl className="dc-facts" style={{ maxWidth: 340 }}>
    <Fact label="Camera" value="Sony FX3" />
    <Fact label="Duration" value="00:04:12:08" />
    <Fact label="Location" value={null} />
    <Fact label="Codec" value="Default (XAVC S-I)" muted />
    <Fact label="File" value="/Volumes/A001/PRIVATE/M4ROOT/CLIP/C0042_2026-09-12_dawn.MP4" oneLine />
  </dl>
);
