import { SegmentedControl } from 'app-kit';

export const Range = () => <SegmentedControl label="Range" options={['Day', 'Week', 'Season']} defaultValue="Week" />;
