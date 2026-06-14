import { router } from '../trpc';
import { getUserRoute } from './get-user';
import { readSettingsRoute } from './read-settings';
import { updateProfileRoute } from './update-profile';

export const userRouter = router({
  get: getUserRoute,
  profile: router({
    update: updateProfileRoute,
  }),
  settings: {
    read: readSettingsRoute,
  },
});
