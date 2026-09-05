import { LocationProvider, Router, Route } from 'preact-iso';
import { Home } from './routes/home';
import { GoRoute, ToiletRoute, CampaignRoute } from './routes/go';
import { NotFound } from './routes/not-found';
import { AppErrorBoundary } from './ui/error-boundary';

export function App() {
  return (
    <AppErrorBoundary>
      <LocationProvider>
        <Router>
          <Route path="/" component={Home} />
          <Route path="/go" component={GoRoute} />
          <Route path="/t/:id" component={ToiletRoute} />
          <Route path="/q/:id" component={CampaignRoute} />
          <Route default component={NotFound} />
        </Router>
      </LocationProvider>
    </AppErrorBoundary>
  );
}
