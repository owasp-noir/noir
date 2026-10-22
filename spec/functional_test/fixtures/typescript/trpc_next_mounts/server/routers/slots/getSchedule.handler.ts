export const getScheduleHandler = async ({ input }: { input: { from: string } }) => {
  return { from: input.from, slots: [] };
};
