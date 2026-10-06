'use client';

import React, { useEffect, useState, useMemo } from 'react';
import { PageHeader, Alert } from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';
import styles from '../notifications/notifications.module.css';

interface Variable {
    key: string;
    label: string;
    description: string;
    example: string;
}

interface Automation {
    id: string;
    key: string;
    name: string;
    description: string;
    audience: string;
    frequency_label: string;
    is_enabled: boolean;
    aisensy_campaign_name: string | null;
    lead_time_minutes: number | null;
    variables: Variable[];
    health: {
        status: string;
        last_run_at: string | null;
        last_success_at: string | null;
        last_failure_at: string | null;
    };
}

export default function WhatsappAutomationsPage() {
    const [automations, setAutomations] = useState<Automation[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // Editing State
    const [editingAutomation, setEditingAutomation] = useState<Automation | null>(null);
    const [editData, setEditData] = useState<{
        is_enabled: boolean;
        aisensy_campaign_name: string;
        lead_time_minutes: number | null;
    } | null>(null);
    const [isSaving, setIsSaving] = useState(false);

    // Test State
    const [testPhone, setTestPhone] = useState('');
    const [isTesting, setIsTesting] = useState(false);

    // Toast System
    const [toast, setToast] = useState<{ type: 'success' | 'error', message: string } | null>(null);

    useEffect(() => {
        fetchAutomations();
    }, []);

    const fetchAutomations = async () => {
        setIsLoading(true);
        setError(null);
        try {
            const response = await fetch('/api/proxy/superadmin/whatsapp-automations');
            if (response.ok) {
                const data = await response.json();
                if (data.success) {
                    setAutomations(data.data || []);
                } else {
                    setError(data.message || 'Failed to load automations.');
                }
            } else {
                setError(`API error: ${response.status} ${response.statusText}`);
            }
        } catch (err: any) {
            console.error('Failed to load automations', err);
            setError(err.message || 'Failed to load automations');
        } finally {
            setIsLoading(false);
        }
    };

    const showToast = (type: 'success' | 'error', message: string) => {
        setToast({ type, message });
        setTimeout(() => setToast(null), 5000);
    };

    const handleEdit = (automation: Automation) => {
        setEditingAutomation(automation);
        setEditData({
            is_enabled: automation.is_enabled,
            aisensy_campaign_name: automation.aisensy_campaign_name || '',
            lead_time_minutes: automation.lead_time_minutes,
        });
        setTestPhone('');
    };

    const closeDrawer = () => {
        setEditingAutomation(null);
        setEditData(null);
    };

    const handleSave = async () => {
        if (!editingAutomation || !editData) return;
        setIsSaving(true);
        try {
            const response = await fetch(`/api/proxy/superadmin/whatsapp-automations/${editingAutomation.key}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(editData),
            });
            const data = await response.json();
            if (response.ok && data.success) {
                await fetchAutomations();
                showToast('success', `${editingAutomation.name} updated successfully.`);
                closeDrawer();
            } else {
                showToast('error', data.message || 'Failed to update automation.');
            }
        } catch (err: any) {
            showToast('error', 'Failed to update automation.');
        } finally {
            setIsSaving(false);
        }
    };

    const handleTest = async () => {
        if (!editingAutomation || !testPhone) {
            showToast('error', 'Please enter a phone number to test.');
            return;
        }

        setIsTesting(true);
        try {
            const response = await fetch(`/api/proxy/superadmin/whatsapp-automations/${editingAutomation.key}/test`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ phone: testPhone }),
            });
            const data = await response.json();
            if (response.ok && data.success) {
                showToast('success', 'Test message queued successfully.');
            } else {
                showToast('error', data.message || 'Failed to queue test message.');
            }
        } catch (err: any) {
            showToast('error', 'Failed to send test message.');
        } finally {
            setIsTesting(false);
        }
    };

    const getStatusLabel = (status: string) => {
        switch (status) {
            case 'NOT_CONFIGURED': return 'Not Configured';
            case 'NEEDS_ATTENTION': return 'Needs Attention';
            default: return status.charAt(0) + status.slice(1).toLowerCase();
        }
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'WORKING': return { bg: '#dcfce7', text: '#166534' };
            case 'READY': return { bg: '#e0e7ff', text: '#3730a3' };
            case 'DISABLED': return { bg: '#f1f5f9', text: '#475569' };
            case 'NOT_CONFIGURED': return { bg: '#fee2e2', text: '#991b1b' };
            case 'NEEDS_ATTENTION': return { bg: '#fef3c7', text: '#92400e' };
            case 'FAILING': return { bg: '#fee2e2', text: '#991b1b' };
            default: return { bg: '#f1f5f9', text: '#475569' };
        }
    };

    const activeCount = useMemo(() => automations.filter(a => a.is_enabled).length, [automations]);

    return (
        <div style={{ padding: '32px', maxWidth: '1200px', margin: '0 auto' }}>
            {toast && (
                <div style={{ position: 'fixed', bottom: 24, right: 24, zIndex: 9999 }}>
                    <Alert tone={toast.type} onClose={() => setToast(null)}>{toast.message}</Alert>
                </div>
            )}

            <div className={styles.header} style={{ marginBottom: 32 }}>
                <div>
                    <h1 style={{ fontSize: 24, fontWeight: 600, color: '#0f172a', marginBottom: 4 }}>WhatsApp Automations</h1>
                    <p style={{ color: '#64748b', margin: 0 }}>Manage automated system WhatsApp messages sent by BookALook.</p>
                </div>
                {!isLoading && automations.length > 0 && (
                    <div style={{ fontSize: 13, color: '#475569', background: '#f8fafc', padding: '6px 12px', borderRadius: 8, border: '1px solid #e2e8f0' }}>
                        {automations.length} Automations &middot; <span style={{ fontWeight: 600, color: activeCount > 0 ? '#10b981' : '#475569' }}>{activeCount} Active</span> &middot; {automations.length - activeCount} Disabled
                    </div>
                )}
            </div>

            {isLoading ? (
                <div className={styles.dashboardCards} style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))' }}>
                    {[1, 2, 3, 4].map(i => (
                        <div key={i} className={styles.card} style={{ minHeight: 200, display: 'flex', flexDirection: 'column', gap: 16 }}>
                            <div style={{ background: '#f1f5f9', height: 24, width: '40%', borderRadius: 4 }} />
                            <div style={{ background: '#f1f5f9', height: 16, width: '80%', borderRadius: 4 }} />
                            <div style={{ background: '#f1f5f9', height: 48, width: '100%', borderRadius: 4 }} />
                        </div>
                    ))}
                </div>
            ) : error ? (
                <Alert tone="error">
                    <strong>Error loading automations</strong><br />
                    {error}
                    <div style={{ marginTop: 12 }}>
                        <button className={styles.testBtn} onClick={fetchAutomations}>Retry</button>
                    </div>
                </Alert>
            ) : automations.length === 0 ? (
                <div className={styles.card} style={{ textAlign: 'center', padding: '64px 20px' }}>
                    <Icon name="info" size={32} style={{ color: '#94a3b8', marginBottom: 16 }} />
                    <h3 style={{ fontSize: 18, color: '#0f172a', margin: '0 0 8px 0' }}>No automations configured</h3>
                    <p style={{ color: '#64748b', margin: 0 }}>System WhatsApp messages will appear here once properly seeded in the database.</p>
                </div>
            ) : (
                <div className={styles.dashboardCards} style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))' }}>
                    {automations.map((automation) => {
                        const statusColor = getStatusColor(automation.health.status);
                        return (
                            <div key={automation.key} className={styles.card} style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
                                    <div style={{ fontWeight: 600, fontSize: 16, color: '#0f172a' }}>{automation.name}</div>
                                    <span style={{ 
                                        padding: '4px 10px', 
                                        borderRadius: 9999, 
                                        fontSize: 12, 
                                        fontWeight: 500,
                                        background: statusColor.bg,
                                        color: statusColor.text
                                    }}>
                                        {getStatusLabel(automation.health.status)}
                                    </span>
                                </div>
                                
                                <p style={{ fontSize: 14, color: '#475569', marginBottom: 24, flex: 1 }}>
                                    {automation.description}
                                </p>
                                
                                <div style={{ marginBottom: 16 }}>
                                    <div style={{ fontSize: 13, fontWeight: 500, color: '#0f172a', display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                                        <Icon name="users" size={14} style={{ color: '#64748b' }} /> {automation.audience}
                                    </div>
                                    <div style={{ fontSize: 13, color: '#64748b', display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                                        <Icon name="clock" size={14} style={{ color: '#94a3b8' }} /> {automation.frequency_label}
                                    </div>
                                    <div style={{ fontSize: 13, color: '#64748b', display: 'flex', alignItems: 'center', gap: 6 }}>
                                        <Icon name="checkCircle" size={14} style={{ color: automation.aisensy_campaign_name ? '#10b981' : '#cbd5e1' }} />
                                        Campaign: {automation.aisensy_campaign_name ? <span style={{ color: '#0f172a', fontWeight: 500 }}>{automation.aisensy_campaign_name}</span> : <span style={{ fontStyle: 'italic' }}>Not configured</span>}
                                    </div>
                                </div>
                                
                                <div style={{ borderTop: '1px solid #e2e8f0', margin: '0 -20px 0 -20px', padding: '16px 20px 0 20px', display: 'flex', justifyContent: 'flex-end' }}>
                                    <button className={styles.editBtn} onClick={() => handleEdit(automation)}>Configure &rarr;</button>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}

            {/* Editor Drawer */}
            {editingAutomation && editData && (
                <div className={styles.drawerOverlay}>
                    <div className={styles.drawerContent} style={{ maxWidth: 640 }}>
                        <div className={styles.drawerHeader}>
                            <div>
                                <h2>{editingAutomation.name}</h2>
                                <p>System WhatsApp Automation</p>
                            </div>
                            <button className={styles.closeBtn} onClick={closeDrawer}>&times;</button>
                        </div>
                        
                        <div className={styles.drawerBody} style={{ flexDirection: 'column', gap: 24 }}>
                            
                            {/* Automation Status */}
                            <div className={styles.sectionBox} style={{ borderLeft: editingAutomation.is_enabled ? '4px solid #10b981' : '4px solid #cbd5e1' }}>
                                <h3 style={{ marginBottom: 16 }}>Automation</h3>
                                
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                                    <div>
                                        <div style={{ fontWeight: 500, fontSize: 14, color: '#0f172a', marginBottom: 4 }}>Status</div>
                                        {editingAutomation.key === 'whatsapp_otp' ? (
                                            <div style={{ fontSize: 13, color: '#64748b', display: 'flex', alignItems: 'center', gap: 6 }}>
                                                <Icon name="info" size={14} /> WhatsApp OTP is currently disabled during development.
                                            </div>
                                        ) : (
                                            <div style={{ fontSize: 13, color: '#64748b' }}>Allow the system to send WhatsApp messages when this event occurs.</div>
                                        )}
                                    </div>
                                    <label className={styles.toggleSwitch} style={{ opacity: editingAutomation.key === 'whatsapp_otp' ? 0.5 : 1, cursor: editingAutomation.key === 'whatsapp_otp' ? 'not-allowed' : 'pointer' }}>
                                        <input 
                                            type="checkbox" 
                                            checked={editData.is_enabled}
                                            disabled={editingAutomation.key === 'whatsapp_otp'}
                                            onChange={(e) => setEditData({...editData, is_enabled: e.target.checked})}
                                        />
                                        <span className={styles.slider}></span>
                                    </label>
                                </div>

                                <div style={{ display: 'flex', gap: 48, borderTop: '1px solid #f1f5f9', paddingTop: 16 }}>
                                    <div>
                                        <div style={{ fontSize: 12, fontWeight: 600, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4 }}>Audience</div>
                                        <div style={{ fontSize: 14, color: '#0f172a' }}>{editingAutomation.audience}</div>
                                    </div>
                                    <div>
                                        <div style={{ fontSize: 12, fontWeight: 600, color: '#94a3b8', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4 }}>Trigger</div>
                                        <div style={{ fontSize: 14, color: '#0f172a', display: 'flex', alignItems: 'center', gap: 6 }}>
                                            {editingAutomation.frequency_label}
                                            {(editingAutomation.key === 'whatsapp_customer_birthday' || editingAutomation.key === 'whatsapp_25_day_reminder') && (
                                                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, background: '#f1f5f9', padding: '2px 6px', borderRadius: 4, fontSize: 11, color: '#64748b' }}>
                                                    <Icon name="info" size={10} /> System rule
                                                </span>
                                            )}
                                        </div>
                                    </div>
                                </div>
                            </div>

                            {/* AiSensy Configuration */}
                            <div className={styles.sectionBox}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                                    <h3 style={{ margin: 0 }}>AiSensy</h3>
                                    {editData.aisensy_campaign_name ? (
                                        <span style={{ fontSize: 12, fontWeight: 500, color: '#10b981', display: 'flex', alignItems: 'center', gap: 4 }}>
                                            <div style={{ width: 6, height: 6, borderRadius: 3, background: '#10b981' }} /> Configured
                                        </span>
                                    ) : (
                                        <span style={{ fontSize: 12, fontWeight: 500, color: editingAutomation.is_enabled ? '#ef4444' : '#64748b', display: 'flex', alignItems: 'center', gap: 4 }}>
                                            <div style={{ width: 6, height: 6, borderRadius: 3, background: editingAutomation.is_enabled ? '#ef4444' : '#64748b' }} /> No campaign configured
                                        </span>
                                    )}
                                </div>
                                
                                <div className={styles.formGroup}>
                                    <label>Campaign Name</label>
                                    <input 
                                        type="text" 
                                        className={styles.input}
                                        value={editData.aisensy_campaign_name}
                                        onChange={(e) => setEditData({...editData, aisensy_campaign_name: e.target.value})}
                                        placeholder="e.g. bal_apt_reminder"
                                    />
                                    <p style={{ fontSize: 12, color: '#64748b', margin: '4px 0 0 0' }}>This must be an approved AiSensy campaign name exactly as it appears in the AiSensy dashboard.</p>
                                </div>

                                {editingAutomation.key === 'whatsapp_appointment_reminder' && (
                                    <div className={styles.formGroup} style={{ marginTop: 20 }}>
                                        <label>Reminder timing (Minutes)</label>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                                            <input 
                                                type="number" 
                                                className={styles.input}
                                                style={{ width: 100 }}
                                                value={editData.lead_time_minutes || ''}
                                                onChange={(e) => setEditData({...editData, lead_time_minutes: parseInt(e.target.value) || 0})}
                                                min="1"
                                            />
                                            <span style={{ fontSize: 14, color: '#334155' }}>minutes before appointment</span>
                                        </div>
                                        <p style={{ fontSize: 12, color: '#64748b', margin: '4px 0 0 0' }}>Customers will receive the reminder within the existing scheduler window (typically batched).</p>
                                    </div>
                                )}
                            </div>

                            {/* Variables */}
                            <div className={styles.sectionBox}>
                                <h3 style={{ marginBottom: 16 }}>Variables</h3>
                                {editingAutomation.variables.length === 0 ? (
                                    <p style={{ fontSize: 13, color: '#64748b', margin: 0 }}>No variables are required for this automation.</p>
                                ) : (
                                    <>
                                        <p style={{ fontSize: 13, color: '#64748b', margin: '0 0 16px 0' }}>Required variables &middot; exact order</p>
                                        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                                            {editingAutomation.variables.map((v, i) => (
                                                <div key={v.key} style={{ display: 'flex', gap: 12, padding: 12, background: '#f8fafc', borderRadius: 8, border: '1px solid #e2e8f0' }}>
                                                    <div style={{ fontWeight: 600, color: '#94a3b8', fontSize: 13 }}>{i + 1}.</div>
                                                    <div style={{ flex: 1 }}>
                                                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                                                            <code style={{ background: 'white', padding: '2px 6px', borderRadius: 4, fontSize: 13, border: '1px solid #cbd5e1', color: '#0f172a', fontWeight: 500 }}>
                                                                {v.key}
                                                            </code>
                                                        </div>
                                                        <div style={{ fontSize: 13, color: '#475569', marginBottom: 4 }}>{v.description}</div>
                                                        <div style={{ fontSize: 12, color: '#64748b' }}>
                                                            Example: <span style={{ color: '#0f172a', fontWeight: 500 }}>{v.key} &rarr; {v.example}</span>
                                                        </div>
                                                    </div>
                                                </div>
                                            ))}
                                        </div>
                                    </>
                                )}
                            </div>

                            {/* Test Campaign */}
                            <div className={styles.sectionBox}>
                                <h3 style={{ marginBottom: 16 }}>Test</h3>
                                <p style={{ fontSize: 13, color: '#64748b', margin: '0 0 16px 0' }}>
                                    Send a test WhatsApp to verify the campaign. Test uses the configured AiSensy approved template and backend-supported variables.
                                </p>
                                
                                <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                                    <div style={{ flex: 1 }} className={styles.formGroup}>
                                        <input 
                                            type="text" 
                                            className={styles.input}
                                            value={testPhone}
                                            onChange={(e) => setTestPhone(e.target.value)}
                                            placeholder="+91XXXXXXXXXX"
                                            disabled={!editingAutomation.is_enabled || !editData.aisensy_campaign_name || editingAutomation.key === 'whatsapp_otp'}
                                        />
                                    </div>
                                    <div style={{ marginTop: '-20px' }}>
                                        <button 
                                            className={styles.testBtn} 
                                            onClick={handleTest}
                                            disabled={isTesting || !editingAutomation.is_enabled || !editData.aisensy_campaign_name || editingAutomation.key === 'whatsapp_otp'}
                                            style={{ opacity: (!editingAutomation.is_enabled || !editData.aisensy_campaign_name || editingAutomation.key === 'whatsapp_otp') ? 0.5 : 1 }}
                                        >
                                            {isTesting ? 'Sending...' : 'Send Test'}
                                        </button>
                                    </div>
                                </div>
                                
                                {(!editingAutomation.is_enabled || !editData.aisensy_campaign_name) && editingAutomation.key !== 'whatsapp_otp' && (
                                    <p style={{ fontSize: 12, color: '#94a3b8', margin: '8px 0 0 0' }}>
                                        Enable the automation and configure a campaign name to test.
                                    </p>
                                )}
                            </div>

                        </div>
                        
                        <div className={styles.drawerFooter}>
                            <button className={styles.editBtn} onClick={closeDrawer}>Cancel</button>
                            <button className={styles.saveBtn} onClick={handleSave} disabled={isSaving}>
                                {isSaving ? 'Saving...' : 'Save Changes'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
