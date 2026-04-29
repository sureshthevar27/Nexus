const express = require('express');
const dotenv = require('dotenv');

dotenv.config();

const initDb = require('./db/init');

const apiRoutes = require('./routes/api');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

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
