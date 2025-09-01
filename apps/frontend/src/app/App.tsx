// Main App Component
// Handles routing, authentication, and application layout

import React, { useEffect } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useMsal } from '@azure/msal-react';
import { InteractionStatus } from '@azure/msal-browser';
import { Layout } from '../shared/components/Layout/Layout';
import { Loading } from '../shared/components/Loading/Loading';
import { ErrorBoundary } from '../shared/components/ErrorBoundary/ErrorBoundary';
import { SDRDashboard } from '../features/sdr/components/SDRDashboard';
import { SDRForm } from '../features/sdr/components/SDRForm';
import { SDRDetails } from '../features/sdr/components/SDRDetails';
import { UserProfile } from '../features/auth/components/UserProfile';
import { LoginPage } from '../features/auth/components/LoginPage';
import { ProtectedRoute } from './components/ProtectedRoute';
import { useAppDispatch } from './store/hooks';
import { setUser, clearUser } from './store/authSlice';

const App: React.FC = () => {
  const { instance, inProgress, accounts } = useMsal();
  const dispatch = useAppDispatch();

  useEffect(() => {
    // Handle authentication state changes
    if (accounts.length > 0) {
      const account = accounts[0];
      dispatch(setUser({
        id: account.localAccountId,
        name: account.name || '',
        email: account.username,
        roles: ['user'], // Default role, can be enhanced with role claims
      }));
    } else if (inProgress === InteractionStatus.None) {
      dispatch(clearUser());
    }
  }, [inProgress, accounts, dispatch]);

  // Show loading spinner during authentication
  if (inProgress === InteractionStatus.Startup ||
      inProgress === InteractionStatus.HandleRedirect) {
    return <Loading />;
  }

  return (
    <ErrorBoundary>
      <Layout>
        <Routes>
          {/* Public Routes */}
          <Route path="/login" element={<LoginPage />} />

          {/* Protected Routes */}
          <Route path="/" element={
            <ProtectedRoute>
              <SDRDashboard />
            </ProtectedRoute>
          } />

          <Route path="/sdr" element={
            <ProtectedRoute>
              <SDRDashboard />
            </ProtectedRoute>
          } />

          <Route path="/sdr/new" element={
            <ProtectedRoute>
              <SDRForm />
            </ProtectedRoute>
          } />

          <Route path="/sdr/:id" element={
            <ProtectedRoute>
              <SDRDetails />
            </ProtectedRoute>
          } />

          <Route path="/profile" element={
            <ProtectedRoute>
              <UserProfile />
            </ProtectedRoute>
          } />

          {/* Catch all route */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Layout>
    </ErrorBoundary>
  );
};

export default App;