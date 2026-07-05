import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp-up to 100 users over 2 minutes
    { duration: '5m', target: 500 },  // Scale up to 500 users over 5 minutes (trigger load)
    { duration: '3m', target: 500 },  // Maintain high load for 3 minutes
    { duration: '2m', target: 0 },    // Cooldown ramp-down to 0 users
  ],
};

export default function () {
  // Target the payment-service endpoint
  http.get('https://app.example.com/api/v1/payments/process');
  sleep(0.1); // 100ms pause between requests per user
}
