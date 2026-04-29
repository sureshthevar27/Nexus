const express = require('express');
const dotenv = require('dotenv');

dotenv.config();

const initDb = require('./db/init');

const apiRoutes = require('./routes/api');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// Allow Flutter web (and any browser client) to call this API
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

app.use('/', apiRoutes);

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

const start = async () => {
  await initDb();

  app.listen(port, () => {
    console.log(`Server running on port ${port}`);
  });
};

start().catch((error) => {
  console.error('Failed to start server:', error);
  process.exit(1);
});
