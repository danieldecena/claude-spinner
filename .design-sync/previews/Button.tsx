import { Button } from 'app-kit';

export const Tinted = () => (
  <div className="dc-row">
    <Button>Preview</Button>
    <Button tint="purple">Tag</Button>
    <Button tint="pink">Favorite</Button>
    <Button tint="orange">Flag</Button>
    <Button tint="mint">Share</Button>
    <Button tint="blue">Info</Button>
  </div>
);

export const Variants = () => (
  <div className="dc-row">
    <Button variant="filled">Import 42 clips</Button>
    <Button variant="gray">Cancel</Button>
    <Button variant="plain">Show all</Button>
    <Button variant="destructive">Delete</Button>
  </div>
);

export const Glass = () => (
  <span style={{ display: 'inline-flex', padding: 10, borderRadius: 22, background: 'linear-gradient(120deg,#5AC8FA,#AF52DE 60%,#FF2D55)' }}>
    <Button variant="glass">Play</Button>
  </span>
);
