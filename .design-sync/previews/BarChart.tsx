import { BarChart } from 'app-kit';

export const Stacked = () => (
  <BarChart
    title="Backup by shoot day"
    summary="Sep 17 is the big day, and most of its clips still have one copy."
    unit="clips"
    series={[{ name: 'Backed up' }, { name: 'One copy' }]}
    data={[
      { label: 'Sep 14', values: [1, 0] }, { label: 'Sep 15', values: [4, 0] }, { label: 'Sep 16', values: [3, 0] },
      { label: 'Sep 17', values: [21, 8] }, { label: 'Sep 18', values: [0, 7] }, { label: 'Sep 19', values: [2, 17] },
    ]}
  />
);

export const Emphasis = () => (
  <BarChart
    title="Readiness by segment"
    summary="The role is the weakest segment, with 1 of 6 items mastered."
    unit="items"
    highlight="The role"
    highlightName="Weakest segment"
    restName="Other segments"
    data={[{ label: 'Front', value: 2 }, { label: 'The role', value: 1 }, { label: 'Stories', value: 2 }, { label: 'Tricky', value: 2 }]}
  />
);
