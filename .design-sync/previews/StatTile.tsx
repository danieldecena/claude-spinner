import { StatTile } from 'app-kit';

export const Tiles = () => (
  <div className="dc-row" style={{ alignItems: 'stretch' }}>
    <StatTile label="Clips today" value="42" />
    <StatTile label="Card used" value="94" unit="%" meter={0.94} attention />
    <StatTile label="Library" value="1.8" unit="TB" meter={0.36} />
  </div>
);
