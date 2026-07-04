import 'custom_haptics_service.dart';

enum FeedbackEvent { select, confirm, reward, error, tick, star, navArrive }

class Feedback {
  static void fire(FeedbackEvent e) {
    switch (e) {
      case FeedbackEvent.reward:
        CustomHapticsService.playRewardCrescendo();
        break;
      case FeedbackEvent.star:
        CustomHapticsService.playStarLock();
        break;
      case FeedbackEvent.confirm:
        CustomHapticsService.playCrispSuccess();
        break;
      case FeedbackEvent.navArrive:
        CustomHapticsService.playRewardCrescendo();
        break;
      case FeedbackEvent.select:
        CustomHapticsService.playTileSelect();
        break;
      case FeedbackEvent.error:
        CustomHapticsService.playHollowDecay();
        break;
      case FeedbackEvent.tick:
        CustomHapticsService.playSoftTick();
        break;
    }
  }
}
