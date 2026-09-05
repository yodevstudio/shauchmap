import { GoScreen } from '../ui/go-screen';

export function GoRoute() {
  return <GoScreen />;
}

/** /t/:toiletId — facility-linked QR/link. toiletId is a HINT only. */
export function ToiletRoute({ id }: { id?: string }) {
  return <GoScreen hintId={id ?? null} />;
}

/** /q/:campaignId — QR/campaign entry. Same GO resolution; id kept in session
 *  only (no analytics, no Firestore write). */
export function CampaignRoute({ id }: { id?: string }) {
  return <GoScreen campaignId={id ?? null} />;
}
