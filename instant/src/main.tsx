import { render } from 'preact';
import './styles/global.css';
import { App } from './app';
import { registerPwa } from './pwa';

const root = document.getElementById('app');
if (root) render(<App />, root);

registerPwa();
